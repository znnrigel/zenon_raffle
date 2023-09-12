import 'package:znn_sdk_dart/znn_sdk_dart.dart';

String formatTime(int seconds) =>
    '${(Duration(seconds: seconds))}'.split('.')[0].padLeft(8, '0');

String escapeMarkdownChars(String message) {
  ['!', '-', '#', '.', '>', '=', '(', ')', '[', ']', '|']
      .forEach((e) => message = message.replaceAll(e, '\\$e'));
  message = message.replaceAll('\\\\', '\\');
  return message;
}

String formatAmount(BigInt amount, Token token, {bool shorten = false}) =>
    shorten
        ? shortenDecimal(AmountUtils.addDecimals(amount, token.decimals))
        : AmountUtils.addDecimals(amount, token.decimals);

String shortenDecimal(String input) {
  if (!input.contains('.')) return input;

  if (input.indexOf('.') + 3 < input.length) {
    return input.substring(0, input.indexOf('.') + 3);
  } else {
    return input;
  }
}

extension MapExtensions on Map {
  Map sortByDescending() {
    List<MapEntry<dynamic, dynamic>> mapEntries = entries.toList();
    mapEntries.sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(mapEntries);
  }

  Map top(int count) {
    Map sortedResult = sortByDescending();
    Map m = {};
    for (var i = 0; i < count; i++) {
      var key = sortedResult.entries.elementAt(i).key;
      var value = sortedResult.entries.elementAt(i).value;
      m[key] = value;
    }
    return m;
  }
}
