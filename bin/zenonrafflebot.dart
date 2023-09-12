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

void main(List<String> args) async {
  try {
    initLogger();
    //Logger.root.level = Level.INFO;
    Logger.root.level = Level.FINE;

    Config.load();
    db = DatabaseService();
    await db.init();

    await initZenon();
    await initIndexer();

    telegram = TelegramPlatform();
    await telegram.initiate();

    await manageRound();
  } catch (e, stackTrace) {
    logger.log(Level.SHOUT, 'main()', e, stackTrace);
  } finally {
    await db.dispose();
  }
  exit(0);
}

Future<void> manageRound() async {
  bool initialRoundStart = true;

  while (raffleServiceEnabled) {
    if (!initialRoundStart) {
      try {
        if (raffle.inProgress) {
          logger.log(Level.FINEST, 'Raffle in progress');
          await Future.delayed(const Duration(seconds: 30));
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
      await newRound(Config.roundDuration, tokens[ppZts]);
    }
  }

  logger.log(Level.WARNING, 'manageRound(): Stopping raffle service');
}

Future<void> newRound(int duration, Token? token) async {
  logger.log(Level.FINE, 'newRound(): duration $duration momentums');
  raffle = Raffle(
    duration: duration,
    token: token!,
  );
  await raffle.init();
}
