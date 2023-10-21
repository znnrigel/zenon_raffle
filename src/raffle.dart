import 'dart:async';
import 'dart:collection';

import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../bin/zenonrafflebot.dart';
import 'config/config.dart';
import 'database/database_service.dart';
import 'functions/format_utils.dart';
import 'functions/functions.dart';
import 'variables/global.dart';
import 'variables/responses.dart';

class Raffle {
  Map<Address, BigInt> players = {}; // <Address address, BigInt amount>
  BigInt pot = BigInt.zero;
  bool inProgress = true;

  Map<int, TokenStandard> votes = {}; // {int telegramId: tokenStandard}
  int voteThreshold = 1;

  int duration; // momentums
  Token token;
  bool isNewRound;

  late int startHeight; // momentum height when we start
  late int endHeight;
  late int roundNumber;
  late int durationSeconds;
  late Timer timer;

  // if the potAddress has extra $token funds, send it to the winner
  BigInt bonus = BigInt.zero;

  Raffle({
    required this.duration,
    required this.token,
    required this.isNewRound,
  });

  init() async {
    try {
      Map roundStatus = await getCurrentRoundStatus();
      int latestRoundNumber = 0;
      if (roundStatus.isNotEmpty) {
        latestRoundNumber = (await getCurrentRoundStatus())['roundNumber'];
      }
      int currentHeight = await frontierMomentum();

      if (isNewRound) {
        // Ensure no pending transactions are in the queue
        while ((await unreceivedTransactions()).list!.isNotEmpty) {
          List<AccountBlock> unreceivedTransactions =
              await allUnreceivedTransactions();
          logger.log(Level.INFO,
              'Clearing ${Config.addressPot}\'s ${unreceivedTransactions.length} unreceived transactions...');
          await refundTx(unreceivedTransactions);
        }

        // Set vars
        startHeight = currentHeight;
        endHeight = startHeight + duration;
        roundNumber = latestRoundNumber + 1;
        durationSeconds = (endHeight - startHeight) * momentumTime;

        logger.log(Level.INFO, 'Starting round #$roundNumber');
      } else {
        Map<String, dynamic> latestRound =
            await selectRound(latestRoundNumber, true);

        startHeight = latestRound['startHeight'];
        endHeight = latestRound['endHeight'];
        roundNumber = latestRoundNumber;
        token = tokens[
            TokenStandard.parse(latestRound['tokenStandard'].toString())]!;
        durationSeconds = (endHeight - currentHeight) * momentumTime;

        logger.log(Level.INFO, 'Resuming round #$roundNumber');
      }

      logger.log(Level.INFO,
          'Momentums: $startHeight - $endHeight / Duration: $duration');
      logger.log(Level.INFO, 'Token: ${token.tokenStandard}');
      logger.log(Level.INFO,
          'Split: ${Config.bpsBurn} bps burn / ${Config.bpsDev} bps dev / ${Config.bpsAirdrop} bps airdrop');

      if (endHeight < currentHeight) {
        await end();
      } else {
        await start();
      }
    } catch (e, stackTrace) {
      logger.log(Level.SEVERE, 'Could not init round', e, stackTrace);
      return;
    }
  }

  start() async {
    try {
      if (isNewRound) {
        await insertNewRound(roundNumber, startHeight, endHeight,
            token.tokenStandard.toString());
        await telegram
            .broadcastToChannel(roundStart(startHeight, endHeight, token));
      }
      timer = await startTimer();
    } catch (e, stackTrace) {
      logger.log(Level.SEVERE, 'Could not start round', e, stackTrace);
    }
  }

  end() async {
    while (await frontierMomentum() < endHeight) {
      await Future.delayed(const Duration(seconds: 5));
    }
    await telegram.broadcastToChannel('Round has ended');

    logger.log(Level.INFO, 'End of round #$roundNumber');

    List<AccountBlock> unreceivedTx = await allUnreceivedTransactions();
    if (unreceivedTx.isEmpty) {
      await endNoWinner();
      return;
    }

    // token is correct and tx was sent in the round timeframe
    List<AccountBlock> bets = unreceivedBets(unreceivedTx);

    // token does not match the one for the round
    // transaction was created outside the boundaries for the round
    List<AccountBlock> refunds = unreceivedInvalid(unreceivedTx);

    if (refunds.isNotEmpty) {
      await refundTx(refunds);
    }

    if (bets.length == 1) {
      await refundTx(bets);
      await endNoWinner();
      return;
    } else if (bets.isNotEmpty) {
      await receiveAll(bets);
      pot = await potSum(bets);
    }

    if (pot == BigInt.zero) {
      await endNoWinner();
      return;
    }

    // this should never happen
    if (pot > BigInt.from(double.maxFinite)) {
      await telegram.broadcastToChannel(raffleSuspended);
      await telegram.broadcastToChannel('Pot size: ${pot.toString()}');
      logger.log(Level.SEVERE, raffleSuspended);
      logger.log(Level.INFO, 'Pot size: ${pot.toString()}');
      inProgress = false;
      raffleServiceEnabled = false;
      return;
    }

    await settleBalances(bets);
  }

  endNoWinner() async {
    logger.log(Level.INFO, roundOverNoWinner);
    await telegram.broadcastToChannel(roundOverNoWinner);
    await updateRoundNoWinner(roundNumber);
    inProgress = false;
  }

  settleBalances(List<AccountBlock> bets) async {
    logger.log(Level.INFO, 'Settling balances for round #$roundNumber');

    // Update the list of current airdrop participants
    // Update db tables
    // Burn or donate portion of the pot
    // Send airdrop
    // Send dev commission
    // Send winner remainder

    await updateCurrentHolders(endHeight);
    await backupCurrentValues(snapshotVars);

    Map<String, dynamic> results = await potCalculations();

    bets = sortBetsByHeight(bets);

    logger.log(Level.FINE, 'Bets Order');
    for (var b in bets) {
      logger.log(Level.FINE,
          '  ${b.confirmationDetail?.momentumHeight} ${b.hash} ${b.amount} ${b.address}');
    }

    Address winner = findWinner(results['winningTicket']!, bets);

    if (winner == Config.addressPot) {
      await telegram.broadcastToChannel(roundOverNoWinner);
      await refundTx(await allUnreceivedTransactions());
      await updateRoundNoWinner(roundNumber);
      inProgress = false;
      return;
    }

    // update db
    await updatePlayers(bets, winner);
    await updateRound(roundNumber, pot, winner, results);
    await updateBets(bets);
    await updateZtsStats(bets, winner, results);

    bool distributionResult = await distributePot(winner, results);
    if (!distributionResult) {
      await telegram.broadcastToChannel(roundOver(
        pot,
        winner,
        results['winningTicket']!,
        token,
        roundNumber,
      ));
      await telegram.broadcastToChannel(raffleSuspended);
      inProgress = false;
      logger.log(
          Level.INFO, 'Round #$roundNumber finished, raffle is suspended');
    }

    bonus > BigInt.zero ? await updateRoundBonus(roundNumber, bonus) : null;

    await telegram.broadcastToChannel(
        roundOver(pot, winner, results['winningTicket']!, token, roundNumber));
    inProgress = false;
    logger.log(Level.INFO, 'Round #$roundNumber finished');
  }

  Future<Timer> startTimer() async => Timer(Duration(seconds: durationSeconds),
      () async => inProgress ? await end() : null);

  Future<Map<String, dynamic>> potCalculations() async {
    Hash hash = await getMomentumHash(endHeight);
    BigInt seed = roundSeed(hash);

    Map<String, dynamic> results = {
      'hash': hash,
      'seed': seed,
      'winningTicket': BigInt.zero,
      'burnAmount': BigInt.zero,
      'devAmount': BigInt.zero,
      'airdropAmount': BigInt.zero,
      'airdropTotal': BigInt.zero,
      'airdropRecipients': 0,
      'winnerAmount': BigInt.zero,
    };

    int airdropRecipients = snapshotVars['holders'].length;
    double burnPercent = Config.bpsBurn / 10000;
    double devPercent = Config.bpsDev / 10000;
    double aidropPercent = Config.bpsAirdrop / 10000;
    double _pot = double.parse(pot.toString());

    BigInt burn = toBigInt(_pot * burnPercent);
    BigInt dev = toBigInt(_pot * devPercent);
    double airdropTotal =
        double.parse((_pot * aidropPercent).toStringAsFixed(0));
    BigInt airdropAmount = toBigInt(airdropTotal / airdropRecipients);
    BigInt winner =
        pot - burn - dev - (airdropAmount * BigInt.from(airdropRecipients));

    int count = 0;
    while (seed % pot == BigInt.zero) {
      seed = BigInt.from(seed / pot);
      count++;
    }

    results['seed'] = seed;
    results['winningTicket'] = seed % pot;
    results['burnAmount'] = burn;
    results['devAmount'] = dev;
    results['airdropAmount'] = airdropAmount;
    results['airdropTotal'] = airdropAmount * BigInt.from(airdropRecipients);
    results['airdropRecipients'] = airdropRecipients;
    results['winnerAmount'] = winner;

    logger.log(Level.FINE, 'New Seed: $seed || Divided $count times');
    logger.log(Level.FINE,
        'Winning ticket: ${seed % pot} (${AmountUtils.addDecimals(seed % pot, token.decimals)})');
    logger.log(
        Level.FINE, 'Pool: ${AmountUtils.addDecimals(pot, token.decimals)}');
    logger.log(
        Level.FINE, 'burn: ${AmountUtils.addDecimals(burn, token.decimals)}');
    logger.log(
        Level.FINE, 'dev: ${AmountUtils.addDecimals(dev, token.decimals)}');
    logger.log(Level.FINE,
        'airdrop total: ${AmountUtils.addDecimals(toBigInt(airdropTotal), token.decimals)}');
    logger.log(Level.FINE,
        'airdrop per bagholder: ${AmountUtils.addDecimals(airdropAmount, token.decimals)}');
    logger.log(Level.FINE,
        'Winner: ${AmountUtils.addDecimals(winner, token.decimals)}');

    return results;
  }

  emergencyRefund() async {
    logger.log(Level.WARNING, 'Admin called emergencyRefund()');
    await refundTx(await allUnreceivedTransactions());
    inProgress = false;
    await telegram.broadcastToChannel(emergencyRefundMessage);
  }

  Future<void> emergencyStop() async {
    logger.log(Level.WARNING, 'Admin called emergencyStop()');
    await emergencyRefund();
    raffleServiceEnabled = false;
  }
}

toBigInt(double value) => BigInt.parse((value).toStringAsFixed(0));

BigInt roundSeed(Hash endHeightHash) {
  BigInt seed = BigInt.zero;

  for (int i = 0; i < endHeightHash.toString().length; i++) {
    seed += BigInt.from(16).pow(endHeightHash.toString().length - i - 1) *
        BigInt.from(int.parse(endHeightHash.toString()[i], radix: 16));
  }

  return seed;
}

Address findWinner(BigInt winningTicket, List<AccountBlock> bets) {
  BigInt currentPoint = BigInt.zero;

  for (AccountBlock b in bets) {
    if (currentPoint + b.amount >= winningTicket &&
        b.address != Config.addressPot) {
      logger.log(Level.FINE,
          'findWinner(): bet - ${b.confirmationDetail!.momentumHeight} ${b.amount} ${b.address} ${b.hash}');
      return b.address;
    }
    currentPoint += b.amount;
  }

  // in case there's a miscalculation, the pot retains the funds until manual intervention
  logger.log(Level.WARNING, 'findWinner(): sending pot to pot address');
  return Config.addressPot;
}

List<AccountBlock> unreceivedBets(List<AccountBlock> unreceivedTx) {
  List<AccountBlock> results = [];
  for (var tx in unreceivedTx) {
    if (tx.tokenStandard == raffle.token.tokenStandard) {
      if (tx.confirmationDetail!.momentumHeight >= raffle.startHeight &&
          tx.confirmationDetail!.momentumHeight <= raffle.endHeight) {
        results.add(tx);
      }
    }
  }
  return results;
}

List<AccountBlock> unreceivedInvalid(List<AccountBlock> unreceivedTx) {
  List<AccountBlock> results = [];
  for (var tx in unreceivedTx) {
    if (tx.tokenStandard != raffle.token.tokenStandard) {
      results.add(tx);
    } else {
      if (tx.confirmationDetail!.momentumHeight < raffle.startHeight ||
          tx.confirmationDetail!.momentumHeight > raffle.endHeight) {
        results.add(tx);
      }
    }
  }
  return results;
}

List<AccountBlock> sortBetsByHeight(List<AccountBlock> bets) {
  // sort by height
  // if heights are the same, sort by hash
  bets.sort((a, b) {
    int cmp = a.confirmationDetail!.momentumHeight
        .compareTo(b.confirmationDetail!.momentumHeight);
    if (cmp != 0) return cmp;
    return a.hash.toString().compareTo(b.hash.toString());
  });
  return bets;
}

SplayTreeMap sortCurrentPlayersByAmount(List<AccountBlock> bets) {
  // consolidate deposits then sort by amount descending

  Map<String, dynamic> players = {};
  for (var b in bets) {
    if (players[b.address.toString()] != null) {
      players[b.address.toString()] += b.amount;
    } else {
      players[b.address.toString()] = b.amount;
    }
  }

  return SplayTreeMap<dynamic, dynamic>.from(
      players, (keys1, keys2) => players[keys2]!.compareTo(players[keys1]!));
}

TokenStandard nextRoundToken() {
  if (raffle.votes.isEmpty) return ([znnZts, qsrZts, ppZts]..shuffle()).first;
  if (raffle.votes.length == 1) return raffle.votes.values.first;
  return getVotes().keys.first!;
}

BigInt getCurrentPotSize(List<AccountBlock> bets) {
  BigInt raffleTickets = BigInt.zero;
  for (AccountBlock b in bets) {
    raffleTickets += b.amount;
  }
  return raffleTickets;
}

Map getVotes() {
  // consolidate votes then sort by amount descending
  Map<TokenStandard, int> voteCount = {};
  raffle.votes.values.forEach((element) {
    if (!voteCount.containsKey(element)) {
      voteCount[element] = 1;
    } else {
      voteCount[element] = voteCount[element]! + 1;
    }
  });
  return voteCount.sortByDescending();
}

Map findLargestBets(Map<Address, BigInt> bets) {
  if (bets.isNotEmpty) {
    Map m = bets.sortByDescending();
    return {m.keys.first: m.values.first};
  }
  return {};
}
