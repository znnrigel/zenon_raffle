import 'dart:async';
import 'dart:collection';
import 'dart:core';

import 'package:teledart/model.dart';
import 'package:teledart/teledart.dart';
import 'package:teledart/telegram.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../config/config.dart';
import '../database/database_service.dart';
import '../raffle.dart';
import '../variables/global.dart';
import '../variables/responses.dart';
import 'format_utils.dart';
import 'functions.dart';

late TeleDart teledart;

class TelegramPlatform {
  // {int telegramId: int lastMessageTime}
  Map<int, int> cooldowns = {};
  int cooldownDuration = 1 * 1000; // ms

  // set to true shortly after the bot has initialized
  bool responsesEnabled = false;

  // reduce query delay and processing overhead while mitigating db dos
  Map<String, dynamic> statsCache = {};

  Future<void> initiate() async {
    logger.log(Level.INFO, '[Zenon Raffle] Initiating Telegram platform...');

    final username = (await Telegram(Config.tgBotKey).getMe()).username;
    teledart = TeleDart(Config.tgBotKey, Event(username!));

    teledart.start();
    await responseFloodMitigation();

    teledart.onCommand('start').listen((msg) async {
      msg.chat.type == 'private' ? handleMessages('start', msg) : null;
      return;
    });

    teledart.onCommand('admin').listen((msg) async {
      if (msg.chat.type == 'private') {
        for (int adminId in Config.admins) {
          if (msg.from?.id == adminId) {
            adminFunctions(msg);
          }
        }
      }
      return;
    });

    teledart.onCommand('info').listen((msg) async {
      handleMessages('info', msg);
      return;
    });

    teledart.onCommand('channel').listen((msg) async {
      handleMessages('channel', msg);
      return;
    });

    teledart.onCommand('vote').listen((msg) async {
      handleMessages('vote', msg);
      return;
    });

    teledart.onCommand('current').listen((msg) async {
      handleMessages('current', msg);
      return;
    });

    teledart.onCommand('tickets').listen((msg) async {
      handleMessages('tickets', msg);
      return;
    });

    teledart.onCommand('leaderboard').listen((msg) async {
      handleMessages('leaderboard', msg);
      return;
    });

    teledart.onCommand('round').listen((msg) async {
      handleMessages('round', msg);
      return;
    });

    teledart.onCommand('stats').listen((msg) async {
      handleMessages('stats', msg);
      return;
    });

    teledart.onMention().listen((msg) async {
      // for debugging
      logger.log(Level.FINER, 'onMention: ${msg.toJson()}');
    });

    // potential commands
    // /register: register address (to display telegram handle in leaderboard)

    logger.log(Level.INFO, '[Zenon Raffle] Telegram platform initiated!');
  }

  void handleMessages(String command, TeleDartMessage msg) async {
    int telegramId = msg.from!.id;

    if (!responsesEnabled) {
      return;
    }

    if (msg.from!.isBot) {
      return;
    }

    if (isFlood(telegramId)) {
      teledart.sendMessage(
          telegramId,
          commandTimeout(cooldownDuration -
              (DateTime.now().millisecondsSinceEpoch -
                  cooldowns[telegramId]!)));
      return;
    }

    cooldowns[telegramId] = DateTime.now().millisecondsSinceEpoch;

    switch (command) {
      case 'start':
        replyToCommand(msg, welcomeMessage);
        break;
      case 'info':
        replyToCommand(msg, infoMenu);
        break;
      case 'channel':
        replyToCommand(msg, raffleChannel);
        break;
      case 'vote':
        await voteForZts(msg);
        break;
      case 'current':
        await getCurrentStats(msg);
        break;
      case 'tickets':
        await getTickets(msg);
        break;
      case 'leaderboard':
        await getLeaderboard(msg);
        break;
      case 'round':
        await getRoundStats(msg);
        break;
      case 'stats':
        await getRaffleStats(msg);
        break;
      default:
        replyToCommand(msg, commandError);
        break;
    }
  }

  bool isFlood(int telegramId) {
    final lastMessageTime = cooldowns[telegramId] ?? 0;
    final timeDifference =
        DateTime.now().millisecondsSinceEpoch - lastMessageTime;
    return timeDifference < cooldownDuration;
  }

  Future<void> getCurrentStats(TeleDartMessage msg) async {
    List<String> message = msg.text!.split(' ');

    if (message.length != 1) {
      replyToCommand(msg, ticketsInfo);
      return;
    }

    BigInt raffleTickets = BigInt.zero;
    BigInt topWager = BigInt.zero;
    String topAddress = '';
    String votesResponse = '';

    try {
      List<AccountBlock> bets =
          unreceivedBets(await allUnreceivedTransactions());

      if (bets.isEmpty) {
      } else {
        raffleTickets = getCurrentPotSize(bets);
        SplayTreeMap sortedBets = sortCurrentPlayersByAmount(bets);
        topWager = sortedBets.values.first;
        topAddress = sortedBets.keys.first;
      }

      Map votes = getVotes();
      votesResponse = '';
      if (votes.isEmpty) {
        votesResponse = 'Random ZTS';
      } else {
        for (int i = 0; i < votes.length; i++) {
          Token t = (await znnClient.embedded.token
              .getByZts(votes.keys.elementAt(i)))!;
          votesResponse += ' *${t.symbol}*: ${votes.values.elementAt(i)} |';
        }
        votesResponse = votesResponse.substring(0, votesResponse.length - 2);
      }

      replyToCommand(
          msg,
          currentStatsResponse(
            raffle.roundNumber,
            raffle.token,
            await frontierMomentum(),
            raffle.endHeight,
            raffleTickets,
            (Config.bpsBurn / 100).toDouble().toStringAsFixed(2),
            (Config.bpsDev / 100).toDouble().toStringAsFixed(2),
            (Config.bpsAirdrop / 100).toDouble().toStringAsFixed(2),
            bets.length,
            topWager,
            topAddress,
            votesResponse,
          ));
    } catch (e) {
      replyToCommand(msg, commandErrorLowSeverity);
      return;
    }
  }

  Future<void> getTickets(TeleDartMessage msg) async {
    List<String> message = msg.text!.split(' ');

    if (message.length == 1) {
      replyToCommand(msg, ticketsInfo);
      return;
    }

    if (!isAddress(message.last)) {
      replyToCommand(msg, commandNotValid);
      return;
    }
    try {
      List<AccountBlock> bets =
          unreceivedBets(await allUnreceivedTransactions());
      bets = sortBetsByHeight(bets);
      Address address = Address.parse(message.last);

      if (bets.isEmpty) {
        replyToCommand(msg, 'There aren\'t any deposits in the current round.');
        return;
      } else {
        // keep track of which tickets are being counted
        BigInt raffleTickets = BigInt.zero;
        BigInt userTotal = BigInt.zero;

        SplayTreeMap sortedBets = sortCurrentPlayersByAmount(bets);

        if (!sortedBets.containsKey(address.toString())) {
          replyToCommand(
              msg, 'This address is not participating in the current round.');
          return;
        }
        String playerRank = '';

        for (var i = 0; i < sortedBets.length; i++) {
          if (sortedBets.entries.elementAt(i).key == address.toString()) {
            if (i == 0) playerRank = '🥇';
            if (i == 1) playerRank = '🥈';
            if (i == 2) playerRank = '🥉';
          }
        }

        String response =
            'Current round\'s raffle tickets for `${address.toString()}`:\n';

        int count = 1;
        for (AccountBlock b in bets) {
          if (b.address == address) {
            userTotal += b.amount;
            response +=
                '$count: *${formatAmount(raffleTickets, raffle.token, shorten: false)}* to *${formatAmount(raffleTickets + b.amount, raffle.token, shorten: false)}*\n';
            count++;
          }
          raffleTickets += b.amount;
        }
        double probability = (userTotal / raffleTickets) * 100;
        response +=
            '\nAddress total = *${formatAmount(userTotal, raffle.token, shorten: false)}*\n';
        response +=
            'Probability: *${probability.toStringAsFixed(2)}%* $playerRank\n';
        response +=
            'Pot total = *${formatAmount(raffleTickets, raffle.token, shorten: false)}*\n';

        replyToCommand(msg, response);
        return;
      }
    } catch (e) {
      replyToCommand(msg, commandErrorLowSeverity);
      return;
    }
  }

  Future<void> getRaffleStats(TeleDartMessage msg) async {
    // edge case: calling /stats in between rounds
    int currentRound = 0;
    while (currentRound == 0) {
      try {
        currentRound = raffle.roundNumber;
      } catch (e) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    List<String> message = msg.text!.split(' ');

    if (message.length == 2) {
      await getPlayerStats(msg);
      return;
    }

    try {
      if (statsCache['latestRound'] != raffle.roundNumber) {
        // update the cache once per round

        // int
        statsCache['latestRound'] = raffle.roundNumber;
        statsCache['countRounds'] = await getCount(Table.rounds);
        statsCache['countBets'] = await getCount(Table.bets);
        statsCache['countPlayers'] = await getCount(Table.players);

        // int
        // may include Config.addressPot
        statsCache['znnPlayerCount'] = await getCount(Table.znnStats);
        statsCache['qsrPlayerCount'] = await getCount(Table.qsrStats);
        statsCache['ppPlayerCount'] = await getCount(Table.ppStats);
        statsCache['znnBetCount'] = await getBetCountForZts(znnZts);
        statsCache['qsrBetCount'] = await getBetCountForZts(qsrZts);
        statsCache['ppBetCount'] = await getBetCountForZts(ppZts);

        // Map<String, BigInt>
        // { pot': BigInt, 'burnAmount': BigInt, 'airdropAmount': BigInt, 'numberOfRounds': BigInt }
        statsCache['znnAmountStats'] = await getAmountStats(znnZts.toString());
        statsCache['qsrAmountStats'] = await getAmountStats(qsrZts.toString());
        statsCache['ppAmountStats'] = await getAmountStats(ppZts.toString());

        // Map<Address, Bigint>
        statsCache['znnLargestBets'] = await getLargestBet(Table.znnStats);
        statsCache['qsrLargestBets'] = await getLargestBet(Table.qsrStats);
        statsCache['ppLargestBets'] = await getLargestBet(Table.ppStats);
      }

      int countRounds = statsCache['countRounds'];
      int countBets = statsCache['countBets'];
      int countPlayers = statsCache['countPlayers'];

      // { tokenStandard: amount }
      Map<TokenStandard, int> numberOfRounds = {};
      Map<TokenStandard, int> numberOfPlayers = {};
      Map<TokenStandard, int> numberOfBets = {};
      Map<TokenStandard, BigInt> totalWagered = {};
      Map<TokenStandard, double> averageBet = {};
      Map<TokenStandard, BigInt> totalBurned = {};
      Map<TokenStandard, BigInt> totalAirdropped = {};

      // { tokenStandard: { Address: BigInt } } // in case there is a tie
      Map largestBets = {};

      for (String token in ['znn', 'qsr', 'pp']) {
        TokenStandard zts;
        switch (token) {
          case 'qsr':
            zts = qsrZts;
          case 'pp':
            zts = ppZts;
          default:
            zts = znnZts;
        }

        numberOfRounds[zts] = int.parse(
            statsCache['${token}AmountStats']['numberOfRounds'].toString());
        numberOfPlayers[zts] = statsCache['${token}PlayerCount'];
        numberOfBets[zts] = statsCache['${token}BetCount'];
        totalWagered[zts] = statsCache['${token}AmountStats']['totalWagered'];

        double avg = numberOfBets[zts] != 0
            ? double.parse(totalWagered[zts].toString()) / numberOfBets[zts]!
            : 0;
        averageBet[zts] = avg != 0 ? double.parse(avg.toStringAsFixed(2)) : avg;

        totalBurned[zts] = statsCache['${token}AmountStats']['totalBurned'];
        totalAirdropped[zts] =
            statsCache['${token}AmountStats']['totalAirdropped'];
        largestBets[zts] = findLargestBets(statsCache['${token}LargestBets']);
      }

      await replyToCommand(
          msg,
          await allRoundStatsResponse(
            countRounds,
            countPlayers,
            countBets,
            numberOfRounds,
            numberOfPlayers,
            numberOfBets,
            totalWagered,
            averageBet,
            totalBurned,
            totalAirdropped,
            largestBets,
          ));
    } catch (e) {
      replyToCommand(msg, commandErrorLowSeverity);
    }
  }

  Future<void> getPlayerStats(TeleDartMessage msg) async {
    List<String> message = msg.text!.split(' ');

    if (!isAddress(message.last)) {
      replyToCommand(msg, commandNotValid);
      return;
    }

    String address = message[1];
    int countBets = 0, countRounds = 0, countWins = 0;
    Map<TokenStandard, int> numberOfRoundsPlayed = {};
    Map<TokenStandard, int> numberOfRoundsWon = {};
    Map<TokenStandard, BigInt> totalWagered = {};
    Map<TokenStandard, BigInt> largestWager = {};
    Map<TokenStandard, BigInt> wonTotal = {};

    try {
      Map<String, dynamic> player = await getPlayer(address);
      if (player.isNotEmpty) {
        countBets = player['numberOfBets'];
        countRounds = player['roundsPlayed'];
        countWins = player['roundsWon'];

        for (String t in [Table.znnStats, Table.qsrStats, Table.ppStats]) {
          Map<String, dynamic> stats = await selectPlayerStats(address, t);
          if (stats.isNotEmpty) {
            TokenStandard zts = znnZts;
            if (t == Table.qsrStats) zts = qsrZts;
            if (t == Table.ppStats) zts = ppZts;

            numberOfRoundsPlayed[zts] = stats['roundsPlayed'];
            numberOfRoundsWon[zts] = stats['roundsWon'];
            totalWagered[zts] = stats['betTotal'];
            largestWager[zts] = stats['largestBet'];
            wonTotal[zts] = stats['wonTotal'];
          }
        }
      }

      replyToCommand(
          msg,
          await playerStatsResponse(
            address,
            countBets,
            countRounds,
            countWins,
            numberOfRoundsPlayed,
            numberOfRoundsWon,
            totalWagered,
            largestWager,
            wonTotal,
          ));
    } catch (e) {
      replyToCommand(msg, commandErrorLowSeverity);
      return;
    }
    return;
  }

  Future<void> getRoundStats(TeleDartMessage msg) async {
    List<String> message = msg.text!.split(' ');

    if (message.length != 2) {
      replyToCommand(msg, roundStatsInfo);
      return;
    }

    try {
      int roundNumber = int.parse(message[1]);
      Map<String, dynamic> roundStats = await selectRound(roundNumber);
      int betCount = await getBetCountForRound(roundNumber);
      if (roundStats.isNotEmpty) {
        Token t = (await znnClient.embedded.token
            .getByZts(roundStats['tokenStandard']))!;
        replyToCommand(msg, roundStatsResponse(roundStats, t, betCount));
      } else {
        replyToCommand(msg, 'Could not retrieve that round information');
      }
      return;
    } catch (e) {
      replyToCommand(msg, roundStatsInfo);
      return;
    }
  }

  Future<void> getLeaderboard(TeleDartMessage msg) async {
    List<String> message = msg.text!.toLowerCase().split(' ');

    if (message.length != 2) {
      replyToCommand(msg, leaderboardInfo);
      return;
    }

    // <tokenStandard: <Address, BigInt>>
    Map stats = {};
    switch (message[1]) {
      case 'winnings':
        stats = await getLeaderboardStats('wonTotal');
      case 'played':
        stats = await getLeaderboardStats('roundsPlayed');
      case 'bets':
        stats = await getLeaderboardStats('largestBet');
      default:
        replyToCommand(msg, leaderboardInfo);
        return;
    }
    replyToCommand(msg, await leaderboardMessage(stats, message[1]));
  }

  Future<void> voteForZts(TeleDartMessage msg) async {
    List<String> message = msg.text!.toLowerCase().split(' ');

    if (message.length == 1) {
      replyToCommand(msg, voteInfo);
      return;
    }

    if (msg.from?.id == null) {
      replyToCommand(
          msg,
          escapeMarkdownChars(
              'Cannot register your vote: invalid Telegram ID'));
      return;
    }

    final lastZtsVote = raffle.votes[msg.from?.id] ?? '';

    switch (message[1]) {
      case 'znn':
        raffle.votes[msg.from!.id] = znnZts;
      case 'qsr':
        raffle.votes[msg.from!.id] = qsrZts;
      case 'pp':
        raffle.votes[msg.from!.id] = ppZts;
      default:
        replyToCommand(
            msg,
            escapeMarkdownChars(
                'Cannot register your vote: invalid token symbol'));
        return;
    }

    if (lastZtsVote != '') {
      replyToCommand(
          msg,
          escapeMarkdownChars(
              'Updated your vote to `${message[1].toUpperCase()}`'));
      return;
    } else {
      replyToCommand(
          msg,
          escapeMarkdownChars(
              'Registered your vote for `${message[1].toUpperCase()}`'));
      return;
    }
  }

  Future<void> adminFunctions(TeleDartMessage msg) async {
    List<String> message = msg.text!.split(' ');

    if (message.length == 1) {
      replyToCommand(msg, adminInfo);
      return;
    }

    logger.log(Level.FINE,
        'adminFunctions() called by ${msg.from!.username}: $message');

    if (message[1] == 'refund') {
      replyToCommand(msg, 'Initiating emergencyRefund()');
      await raffle.emergencyRefund();
      return;
    }

    if (message[1] == 'stop') {
      replyToCommand(msg, 'Initiating emergencyStop()');
      await raffle.emergencyStop();
      return;
    }

    if (message[1] == 'update' && message.length == 4) {
      int amount = 0;
      try {
        amount = int.parse(message[3]);
      } catch (e) {
        replyToCommand(msg, adminInfo);
        return;
      }

      switch (message[2]) {
        case 'airdrop':
          if (amount >= 0 && amount <= 2500) {
            broadcastToChannel(adminUpdatedValueAlert(
                'airdrop percentage',
                '${(Config.bpsAirdrop / 100).toDouble().toStringAsFixed(2)}%',
                '${(amount / 100).toDouble().toStringAsFixed(2)}%'));
            Config.bpsAirdrop = amount;
          } else {
            replyToCommand(msg, 'Should not airdrop more than 25%');
            return;
          }
        case 'burn':
          if (amount >= 0 && amount <= 1000) {
            broadcastToChannel(adminUpdatedValueAlert(
                'burn/donation percentage',
                '${(Config.bpsBurn / 100).toDouble().toStringAsFixed(2)}%',
                '${(amount / 100).toDouble().toStringAsFixed(2)}%'));
            Config.bpsBurn = amount;
          } else {
            replyToCommand(msg, 'Should not burn more than 10%');
            return;
          }
        case 'dev':
          if (amount >= 0 && amount <= 1000) {
            broadcastToChannel(adminUpdatedValueAlert(
                'dev percentage',
                '${(Config.bpsDev / 100).toStringAsFixed(2)}%',
                '${(amount / 100).toDouble().toStringAsFixed(2)}%'));
            Config.bpsDev = amount;
          } else {
            replyToCommand(msg, 'Dev should not receive more than 10%');
            return;
          }
        case 'duration':
          if (amount >= 30) {
            broadcastToChannel(adminUpdatedValueAlert(
                'round duration (momentums)',
                '${Config.roundDuration}',
                '$amount'));
            Config.roundDuration = amount;
          } else {
            replyToCommand(
                msg, 'Round duration should be at least 30 momentums');
            return;
          }
        default:
          replyToCommand(msg, adminInfo);
          return;
      }
    }
  }

  Future<Map> getLeaderboardStats(String column) async {
    Map<TokenStandard, Map> stats = {};
    for (String t in [Table.znnStats, Table.qsrStats, Table.ppStats]) {
      Map<Address, BigInt> result = await selectLeaderboardStats(t, column);
      if (result.isNotEmpty) {
        int count = result.length >= 3 ? 3 : result.length;
        if (t == Table.znnStats) stats[znnZts] = result.top(count);
        if (t == Table.qsrStats) stats[qsrZts] = result.top(count);
        if (t == Table.ppStats) stats[ppZts] = result.top(count);
      }
    }
    return stats;
  }

  // If users spam commands while the bot is offline,
  // the bot will respond them when it's back online unless we discard them
  Future<Timer> responseFloodMitigation() async =>
      Timer(Duration(seconds: 5), () async => responsesEnabled = true);

  broadcastToChannel(String message) => teledart.sendMessage(
      Config.channel, escapeMarkdownChars(message.toString()),
      parseMode: 'MarkdownV2');

  replyToCommand(TeleDartMessage msg, String response) =>
      msg.reply(escapeMarkdownChars(response), parseMode: 'MarkdownV2');
}