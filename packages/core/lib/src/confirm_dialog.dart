import 'package:flutter/material.dart';

/// The one "are you sure?" both apps ask before destroying something
/// (2026-08-15, Samyak): Nivaat's delete-court (N20) and delete-alarm, and
/// Arunoday's delete-location.
///
/// A shared shell rather than three `AlertDialog`s, because three copies is
/// how the two apps drift apart on the same gesture — and this repo has the
/// scar for it already: N20's warning shipped an ungrammatical singular for a
/// fortnight because nothing could name the string. **Only the shell is here.**
/// Every word is still built by the app that asks, so each message stays a
/// pure builder its own `message_test` can assert.
///
/// Returns true only when the user actually confirms — a dismissed barrier and
/// a `Cancel` both answer false, so the caller never has to read a null.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final text = Theme.of(context).textTheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: text.labelSmall),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
