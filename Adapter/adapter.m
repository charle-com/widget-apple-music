// Adaptateur MediaRemote de Platine.
//
// macOS refuse l'accès à MediaRemote (piste en cours, file d'attente) aux apps tierces, mais l'accorde aux
// binaires système. Cette bibliothèque est donc chargée dans /usr/bin/perl (voir Adapter.swift) et écrit sur
// la sortie standard une ligne JSON à chaque changement d'état. Dans l'autre sens, elle lit sur l'entrée
// standard les commandes de l'app hôte (play, pause, next, previous) et les transmet au lecteur en cours.
//
// API privée : vérifiée sur macOS 27.2.1 le 11/11/2026. Si une mise à jour la casse, l'adaptateur n'émet
// plus rien et le widget garde le dernier état connu.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void *MR;
static dispatch_queue_t Q;
static NSString *lastLine;
static BOOL scheduled;
static const NSUInteger kQueueLength = 24;

static id kv(id obj, NSString *key) {
  @try { return [obj valueForKey:key]; } @catch (id e) { return nil; }
}
static NSString *str(id v) { return [v isKindOfClass:NSString.class] ? v : @""; }
static double dbl(id v) { return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : 0; }
// Identifiant de catalogue Apple Music, vide si la piste n'en a pas (fichier local, par exemple).
static NSString *storeID(id v) {
  return ([v isKindOfClass:NSNumber.class] && [v longLongValue] > 0) ? [NSString stringWithFormat:@"%lld", [v longLongValue]] : @"";
}

// Pour une piste de la bibliothèque, Musique ne donne pas d'adresse de pochette mais un identifiant interne.
// L'image de la piste en cours, elle, est jointe aux infos de lecture : on la pose dans un fichier temporaire
// que l'app hôte lit. Un seul fichier à la fois, nommé d'après l'identifiant de la pochette.
static NSString *nowArtID;
static NSString *nowArtPath;
static NSString *nowArtFile(NSDictionary *info) {
  NSString *artID = str(info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"]);
  NSData *data = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
  if (!artID.length || ![data isKindOfClass:NSData.class] || data.length == 0) return nil;
  if ([artID isEqualToString:nowArtID]) return nowArtPath;
  uint64_t h = 1469598103934665603ULL;  // FNV-1a : un nom de fichier stable d'un lancement à l'autre
  for (const unsigned char *c = (const unsigned char *)artID.UTF8String; *c; c++) { h ^= *c; h *= 1099511628211ULL; }
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"platine-art-%016llx", h]];
  if (![data writeToFile:path atomically:YES]) return nil;
  if (nowArtPath && ![nowArtPath isEqualToString:path]) [NSFileManager.defaultManager removeItemAtPath:nowArtPath error:nil];
  nowArtID = artID;
  nowArtPath = path;
  return path;
}

static void emit(NSDictionary *info, BOOL playing, id queue) {
  NSMutableArray *items = [NSMutableArray array];
  NSArray *content = queue ? kv(queue, @"contentItems") : nil;
  NSString *nowArt = str(info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"]);
  NSString *nowFile = nowArtFile(info) ?: @"";
  if ([content isKindOfClass:NSArray.class]) {
    for (id item in content) {
      id md = kv(item, @"metadata");
      if (!md) continue;
      // La pochette arrive sous trois formes : une adresse (radio, catalogue), sinon l'identifiant de
      // catalogue de la piste (l'app hôte retrouve l'adresse), sinon l'image locale de la piste en cours.
      NSString *art = str(kv(md, @"artworkIdentifier"));
      NSString *store = storeID(kv(md, @"iTunesStoreIdentifier"));
      if (!store.length) store = storeID(kv(md, @"iTunesStoreSubscriptionIdentifier"));
      [items addObject:@{
        @"id": str(kv(item, @"identifier")),
        @"title": str(kv(md, @"title")),
        @"artist": str(kv(md, @"trackArtistName")),
        @"album": str(kv(md, @"albumName")),
        @"duration": @(dbl(kv(md, @"duration"))),
        @"art": [art hasPrefix:@"http"] ? art : @"",
        @"store": store,
        @"file": (art.length && [art isEqualToString:nowArt]) ? nowFile : @"",
      }];
    }
  }

  // La file part de la piste en cours. Pendant une transition, elle peut encore commencer une piste trop tôt.
  NSString *nowID = str(info[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"]);
  if (nowID.length) {
    NSUInteger idx = [items indexOfObjectPassingTest:^BOOL(NSDictionary *it, NSUInteger i, BOOL *stop) {
      return [it[@"id"] isEqualToString:nowID];
    }];
    if (idx != NSNotFound && idx > 0) [items removeObjectsInRange:NSMakeRange(0, idx)];
  }
  // File illisible : on garde au moins la piste en cours, tirée des infos de lecture.
  NSString *title = str(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
  if (items.count == 0 && title.length) {
    [items addObject:@{
      @"id": nowID.length ? nowID : title,
      @"title": title,
      @"artist": str(info[@"kMRMediaRemoteNowPlayingInfoArtist"]),
      @"album": str(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]),
      @"duration": @(dbl(info[@"kMRMediaRemoteNowPlayingInfoDuration"])),
      @"art": [nowArt hasPrefix:@"http"] ? nowArt : @"",
      @"store": storeID(info[@"kMRMediaRemoteNowPlayingInfoiTunesStoreIdentifier"]),
      @"file": nowFile,
    }];
  }

  // Le drapeau « en lecture » de l'app et les infos de piste ne changent pas au même instant : à la reprise,
  // le drapeau passe à vrai alors que la position date encore de la mise en pause, et à la pause il reste
  // vrai deux secondes de trop. La vitesse de lecture, elle, change avec la position : c'est elle qui fait foi.
  NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
  if ([rate isKindOfClass:NSNumber.class]) playing = rate.doubleValue > 0;

  NSDate *ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
  NSDictionary *out = @{
    @"music": @([info[@"kMRMediaRemoteNowPlayingInfoIsMusicApp"] boolValue]),
    @"playing": @(playing),
    @"elapsed": @(dbl(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"])),
    @"timestamp": @([ts isKindOfClass:NSDate.class] ? ts.timeIntervalSince1970 : NSDate.date.timeIntervalSince1970),
    @"items": items,
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
  if (!data) return;
  NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if ([line isEqualToString:lastLine]) return;
  lastLine = line;
  fputs(line.UTF8String, stdout);
  fputc('\n', stdout);
  fflush(stdout);
}

static void fetch(void) {
  void (*getInfo)(dispatch_queue_t, void (^)(CFDictionaryRef)) = dlsym(MR, "MRMediaRemoteGetNowPlayingInfo");
  void (*getPlaying)(dispatch_queue_t, void (^)(Boolean)) = dlsym(MR, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
  Class reqClass = objc_getClass("MRPlaybackQueueRequest");
  Class destClass = objc_getClass("MRDestination");
  SEL initSel = sel_registerName("initWithRange:");
  SEL metaSel = sel_registerName("setIncludeMetadata:");
  SEL perfSel = sel_registerName("performRequestForDestination:completion:");
  SEL localSel = sel_registerName("localDestination");
  if (!getInfo || !getPlaying) return;
  BOOL canQueue = reqClass && destClass && [reqClass instancesRespondToSelector:initSel]
    && [reqClass instancesRespondToSelector:metaSel] && [reqClass instancesRespondToSelector:perfSel]
    && [destClass respondsToSelector:localSel];

  getInfo(Q, ^(CFDictionaryRef d) {
    NSDictionary *info = d ? [(__bridge NSDictionary *)d copy] : @{};
    getPlaying(Q, ^(Boolean playing) {
      if (!canQueue) { emit(info, playing, nil); return; }
      id req = ((id (*)(id, SEL, NSRange))objc_msgSend)([reqClass alloc], initSel, NSMakeRange(0, kQueueLength));
      ((void (*)(id, SEL, BOOL))objc_msgSend)(req, metaSel, YES);
      id dest = ((id (*)(id, SEL))objc_msgSend)(destClass, localSel);
      ((void (*)(id, SEL, id, id))objc_msgSend)(req, perfSel, dest, ^(id queue, id err) {
        dispatch_async(Q, ^{ emit(info, playing, queue); });
      });
    });
  });
}

// Les notifications arrivent en rafale à chaque changement de piste : une seule lecture, 250 ms après la première.
static void schedule(void) {
  dispatch_async(Q, ^{
    if (scheduled) return;
    scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), Q, ^{
      scheduled = NO;
      fetch();
    });
  });
}

// Commandes de MediaRemote : 0 = lecture, 1 = pause, 4 = piste suivante, 5 = piste précédente.
// Lecture et pause sont envoyées séparément plutôt qu'en bascule : un clic répété ou reçu pendant une
// mise en mémoire tampon ne peut pas inverser l'état par erreur.
static void command(NSString *name) {
  Boolean (*send)(uint32_t, id) = dlsym(MR, "MRMediaRemoteSendCommand");
  if (!send) return;
  if ([name isEqualToString:@"play"]) send(0, nil);
  else if ([name isEqualToString:@"pause"]) send(1, nil);
  else if ([name isEqualToString:@"next"]) send(4, nil);
  else if ([name isEqualToString:@"previous"]) send(5, nil);
  else return;
  schedule();
}

// Point d'entrée, appelé depuis perl. Ne rend jamais la main.
void platine_run(void) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  MR = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
  if (!MR) { fputs("{\"error\":\"MediaRemote introuvable\"}\n", stdout); exit(2); }
  Q = dispatch_queue_create("platine.adapter", DISPATCH_QUEUE_SERIAL);

  void (*registerNotifs)(dispatch_queue_t) = dlsym(MR, "MRMediaRemoteRegisterForNowPlayingNotifications");
  if (registerNotifs) registerNotifs(Q);
  const char *names[] = {
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    "kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification",
    "kMRNowPlayingPlaybackQueueChangedNotification",
    "kMRPlaybackQueueContentItemsChangedNotification",
  };
  for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
    NSString *__unsafe_unretained *sym = (NSString *__unsafe_unretained *)dlsym(MR, names[i]);
    NSString *name = (sym && *sym) ? *sym : [NSString stringWithUTF8String:names[i]];
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
      schedule();
    }];
  }

  if (getenv("PLATINE_ONCE")) {
    fetch();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), Q, ^{ exit(0); });
    dispatch_main();
  }

  // Une commande par ligne. Entrée fermée : l'app hôte a disparu, l'adaptateur s'arrête avec elle.
  dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, Q);
  dispatch_source_set_event_handler(input, ^{
    char buffer[256];
    ssize_t n = read(STDIN_FILENO, buffer, sizeof(buffer) - 1);
    if (n <= 0) exit(0);
    buffer[n] = 0;
    NSString *text = [NSString stringWithUTF8String:buffer] ?: @"";
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
      NSString *name = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      if (name.length) command(name);
    }
  });
  dispatch_resume(input);

  // Filet : relecture toutes les 15 s (une notification peut se perdre), et arrêt si l'app hôte a disparu.
  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, Q);
  dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
  dispatch_source_set_event_handler(timer, ^{
    if (getppid() == 1) exit(0);
    fetch();
  });
  dispatch_resume(timer);
  dispatch_main();
}
