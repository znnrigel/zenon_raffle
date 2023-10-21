// Zenon Raffle Bot

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../src/config/config.dart';
import '../src/database/database_service.dart';
import '../src/functions/functions.dart';
import '../src/raffle.dart';
import '../src/variables/global.dart';

late final TelegramPlatform telegram;

main(List<String> args) async {
  try {
    initLogger();
    //Logger.root.level = Level.INFO;
    Logger.root.level = Level.FINER;

    Config.load();
    await DatabaseService().init();

    await initZenon();
    await initIndexer();

    telegram = TelegramPlatform();
    await initTelegram();

    await manageRound();
  } catch (e, stackTrace) {
    logger.log(Level.SHOUT, 'main()', e, stackTrace);
  } finally {
    await DatabaseService().dispose();
  }
  exit(0);
}

manageRound() async {
  bool initialRoundStart = true;

  while (raffleServiceEnabled) {
    if (!initialRoundStart) {
      try {
        if (raffle.inProgress) {
          logger.log(Level.FINEST, 'Raffle in progress');
          await Future.delayed(const Duration(seconds: 30));
          await nodeConnection();
          await antiDos();
        } else {
          await newRound(Config.roundDuration, tokens[nextRoundToken()]!);
        }
      } catch (e) {
        logger.log(Level.SEVERE, 'manageRound(): $e');
      }
    } else {
      // start the first round
      initialRoundStart = false;
      await newRound(Config.roundDuration,
          tokens[([znnZts, qsrZts, ppZts]..shuffle()).first]);
    }
  }

  logger.log(Level.WARNING, 'manageRound(): Stopping raffle service');
}

newRound(int duration, Token? token) async {
  logger.log(Level.FINE, 'newRound(): duration $duration momentums');
  Map<String, dynamic> currentRound = await getCurrentRoundStatus();
  bool isNewRound = true;

  if (currentRound.isNotEmpty) {
    isNewRound = !currentRound['active'];
  }

  raffle = Raffle(
    duration: duration,
    token: token!,
    isNewRound: isNewRound,
  );
  await raffle.init();
}

initTelegram() async {
  await runZonedGuarded(() async {
    await telegram.initiate();
  }, (error, stacktrace) async {
    // this should never be reached

    // Note: runZonedGuarded doesn't seem to re-initialize correctly
    // it will call telegram.initiate() once more
    // if that fails, the script terminates
    logger.log(
        Level.WARNING, 'initTelegram(): Telegram error: $error\n$stacktrace');
    await Future.delayed(const Duration(seconds: 30));
    logger.log(Level.INFO, 'runZonedGuarded -> 30 sec delay -> initTelegram()');
    await initTelegram();
  });
}
