import 'package:znn_sdk_dart/znn_sdk_dart.dart' hide logger;

import '../config/config.dart';
import '../functions/format_utils.dart';
import 'global.dart';

String welcomeMessage = '🖖 Welcome, 👽!\n\n'
    '🛸 @zenonrafflebot is a daily lottery hosted on NoM!\n'
    '💰 Revenue is split across the winner, AZ donations, burns, the dev, and airdrop recipients\n\n'
    '🌀 Type `/info` for more details';

String infoMenu = '⚡ Zenon Raffle: Info Menu ⚡\n'
    '*Announcements*: $raffleChannel\n'
    '*Docs*: $docsLink\n\n'
    '*Commands*:\n'
    'ℹ️ `/info`\n'
    '$channelInfo\n'
    '$voteInfo\n\n'
    '*Stats Commands*:\n'
    '$currentInfo\n'
    '$ticketsInfo\n'
    '$leaderboardInfo\n'
    '$roundStatsInfo\n'
    '$allRoundsStatsInfo\n\n';

String channelInfo = '📢 `/channel` - announcement channel';
String voteInfo =
    '🗳️ `/vote <znn/qsr/pp>` - vote for the next round\'s raffle token';

String currentInfo = '🌀 `/current` - displays current round details';
String ticketsInfo =
    '🎫 `/tickets <address>` - displays this round\'s raffle tickets for an address';
String leaderboardInfo = '🏆 `/leaderboard` <bets/played/winnings>';
String roundStatsInfo =
    '💰 `/round <number>` - displays stats for a previous round';
String allRoundsStatsInfo =
    '📊 `/stats [address]` - displays stats for all rounds or a specific address';

String adminInfo = 'Usage: `/admin` \n'
    '  *refund* - refunds all pending unreceived and starts a new round\n'
    '  *stop* - refunds all pending unreceived and stops the raffle service\n'
    '  *update* <variable> <value>\n'
    '  - airdrop [0, 2500]\n'
    '  - burn [0, 1000]\n'
    '  - dev [0, 1000]\n'
    '  - duration [>=30]\n';

String commandTimeout(int cooldownRemaining) =>
    '⏳ Please wait ${cooldownRemaining / 1000} seconds before sending another message.';

String commandNotValid = '❌ Invalid command';
String commandErrorLowSeverity = '❌ Something went wrong, please try again.';
String commandError = '❌ Something went wrong, please contact @znnrigel';

String roundStart(int start, int end, Token token) {
  return '🎟️ *New Round* 🎟️\n'
      'Momentums: *$start* to *$end*\n'
      'Duration: *${formatTime((end - start) * momentumTime)}*\n'
      'Token: ${tokenEmoji(token)}*${token.symbol}* `${token.tokenStandard}`\n'
      'Deposit address: `${Config.addressPot}`';
}

String roundOver(BigInt pot, Address winner, BigInt winningTicket, Token token,
        int roundNumber) =>
    '🎉 *Round #$roundNumber Results* 🎉\n'
    'Winner: `${winner.toString()}`\n'
    'Pot: *${formatAmount(pot, token)} ${token.symbol}*\n'
    'Winning ticket: *${formatAmount(winningTicket, token, shorten: false)}*\n\n'
    'Type `/round $roundNumber` for more details';

String roundOverNoWinner = 'Round Over: no winner';
String emergencyRefundMessage = '🛑 This round has been canceled 🛑\n'
    '*All deposits for this round were refunded*';
String raffleSuspended =
    'The raffle service is temporarily suspended while we calculate and distribute the funds.';

String currentStatsResponse(
  int roundNumber,
  Token token,
  int currentHeight,
  int endHeight,
  BigInt totalTickets,
  String burn,
  String dev,
  String airdrop,
  int betCount,
  BigInt topWager,
  String topAddress,
  String votes,
) =>
    '*Round #$roundNumber*\n'
    'Time remaining: *${formatTime((endHeight - currentHeight) * momentumTime)}* (end height *$endHeight*)\n'
    'Token: ${tokenEmoji(token)}*${token.symbol}* `${token.tokenStandard}`\n'
    'Total tickets: *${totalTickets.toString()}*\n'
    'Number of deposits: *$betCount*\n'
    '${topWager != BigInt.zero ? '👑 *${formatAmount(topWager, token, shorten: true)} ${token.symbol}* | `$topAddress`\n' : ''}'
    'Votes: $votes\n'
    'Burn: *$burn*% | Dev: *$dev*% | Airdrop: *$airdrop*%\n';

String roundStatsResponse(
        Map<String, dynamic> stats, Token token, int betCount) =>
    '📊 *Round #${stats['roundNumber']}* 📊\n '
    'Winner: `${stats['winner']}`\n'
    'Pot: *${formatAmount(stats['pot'], token, shorten: true)} ${token.symbol}*\n'
    'Hash: `${stats['hash']}`\n'
    'Seed: *${stats['seed']}*\n'
    'Total tickets: *${stats['pot']}*\n'
    'Winning ticket: *${formatAmount(stats['winningTicket'], token)}*\n\n'
    'Number of Deposits: $betCount\n'
    'Winner amount: *${formatAmount(stats['winnerAmount'], token, shorten: true)} ${token.symbol}* 🎉'
    '${stats['winnerBonus'] > BigInt.zero ? ' Bonus: *${formatAmount(stats['winnerBonus'], token, shorten: true)} ${token.symbol}* 💰\n' : '\n'}'
    'Burned amount: *${formatAmount(stats['burnAmount'], token, shorten: true)} ${token.symbol}* 🔥\n'
    'Dev amount: *${formatAmount(stats['devAmount'], token, shorten: true)} ${token.symbol}* 👽\n'
    'Airdrop amount: *${formatAmount(stats['airdropAmount'], token, shorten: true)} ${token.symbol}* 💸 *${stats['airdropRecipients']}* recipients';

Future<String> allRoundStatsResponse(
  int countRounds,
  int countPlayers,
  int countBets,
  Map<TokenStandard, int> numberOfRounds,
  Map<TokenStandard, int> numberOfPlayers,
  Map<TokenStandard, int> numberOfBets,
  Map<TokenStandard, BigInt> totalWagered,
  Map<TokenStandard, double> averageBet,
  Map<TokenStandard, BigInt> totalBurned,
  Map<TokenStandard, BigInt> totalAirdropped,
  Map largestBets,
) async {
  List<String> stats = [];

  for (Token t in tokens.values) {
    TokenStandard zts = t.tokenStandard;

    if (numberOfRounds[zts]! > 0) {
      Token token = (await znnClient.embedded.token.getByZts(zts))!;

      String largest = '';
      largestBets[zts]?.keys.forEach((e) => largest += '  🏆 `$e` 🏆\n');

      stats.add('*${token.symbol}*\n'
          '  Rounds: ${numberOfRounds[zts]}\n'
          '  Players: ${numberOfPlayers[zts]}\n'
          '  Deposits: ${numberOfBets[zts]}\n'
          '  Total wagered: *${formatAmount(totalWagered[zts]!, token)} ${token.symbol}*\n'
          '  Average deposit: *${formatAmount(BigInt.from(averageBet[zts]!), token)} ${token.symbol}*\n'
          '  Total ${zts == ppZts ? 'burned' : 'AZ donations'}: *${formatAmount(totalBurned[zts]!, token)} ${token.symbol}*\n'
          '  Total airdropped: *${formatAmount(totalAirdropped[zts]!, token)} ${token.symbol}*\n'
          '  Largest bet${largestBets[zts]!.keys.length > 1 ? 's' : ''}: *${formatAmount(largestBets[zts]!.values.first, token)}  ${token.symbol}*\n'
          '$largest\n');
    }
  }
  String results = '';
  stats.forEach((e) => results += e);

  return '📊 *Round Stats* 📊\n'
      'Rounds: $countRounds\n'
      'Players: $countPlayers\n'
      'Bets: $countBets\n\n'
      '$results';
}

Future<String> playerStatsResponse(
  String address,
  int countBets,
  int countRounds,
  int countWins,
  Map<TokenStandard, int> numberOfRoundsPlayed,
  Map<TokenStandard, int> numberOfRoundsWon,
  Map<TokenStandard, BigInt> totalWagered,
  Map<TokenStandard, BigInt> largestWager,
  Map<TokenStandard, BigInt> wonTotal,
) async {
  List<String> stats = [];

  for (Token t in tokens.values) {
    TokenStandard zts = t.tokenStandard;

    if (numberOfRoundsPlayed[zts] != null && numberOfRoundsPlayed[zts]! > 0) {
      Token token = (await znnClient.embedded.token.getByZts(zts))!;

      stats.add('*${token.symbol}*\n'
          '  Rounds won/played: *${numberOfRoundsWon[zts]} / ${numberOfRoundsPlayed[zts]}*\n'
          '  Total wagered: *${formatAmount(totalWagered[zts]!, token, shorten: true)} ${token.symbol}*\n'
          '  Largest deposit: *${formatAmount(largestWager[zts]!, token, shorten: true)}  ${token.symbol}*\n'
          '  Total won: *${formatAmount(wonTotal[zts]!, token, shorten: true)}  ${token.symbol}*\n'
          '\n');
    }
  }
  String results = '';
  stats.forEach((e) => results += e);

  return '📊 *Stats*: `$address` 📊\n'
      'Rounds: *$countRounds*\n'
      'Wins: *$countWins*\n'
      'Deposits: *$countBets*\n\n'
      '$results';
}

// <tokenStandard: <Address, BigInt>>
Future<String> leaderboardMessage(Map players, String messageType) async {
  List<String> topPlayers = [];

  String title = '';
  String body = '';

  switch (messageType) {
    case 'winnings':
      title = 'Amount Won';
      body = 'won';
    case 'played':
      title = 'Rounds Played';
      body = 'rounds';
    case 'bets':
      title = 'Bets';
      body = '';
  }

  for (Token t in tokens.values) {
    TokenStandard zts = t.tokenStandard;
    if (players.containsKey(zts)) {
      topPlayers.add('\n*${t.symbol}*\n');

      for (var player in players[zts]!.entries) {
        topPlayers.add(
            '  ${messageType != 'played' ? '*${formatAmount(player.value, t, shorten: true)} ${t.symbol}* ' : '*${player.value}*'} $body: `${player.key}`\n');
      }
    }
  }
  String results = '';
  topPlayers.forEach((e) => results += e);

  return '📊 *Leaderboard: $title* 📊\n'
      '$results';
}

String tokenEmoji(Token token) {
  String emoji = '';
  if (token.tokenStandard == znnZts) {
    emoji = '🟢';
  } else if (token.tokenStandard == qsrZts) {
    emoji = '🔵';
  } else if (token.tokenStandard == ppZts) {
    emoji = '🟣';
  }
  return emoji;
}

String adminUpdatedValueAlert(
        String variable, String oldValue, String newValue) =>
    'Admin updated *$variable*: $oldValue => $newValue';
