import 'package:flutter/widgets.dart';

import '../../data/models/activity.dart';
import '../../l10n/strings.dart';

String walletStatusLabel(BuildContext context, MyRegistration ticket) {
  final strings = stringsOf(context);
  if (ticket.registrationStatus == 4 && ticket.ticketState == TicketState.voided) {
    return strings.ticketWalletExpired;
  }
  return switch (ticket.ticketState) {
    TicketState.ready => strings.ticketWalletReady,
    TicketState.pending => strings.ticketWalletPending,
    TicketState.done => strings.ticketWalletVerified,
    TicketState.voided => strings.ticketWalletCancelled,
  };
}

String walletCta(BuildContext context, TicketState state) => switch (state) {
  TicketState.ready => stringsOf(context).ticketWalletPlay,
  TicketState.pending => stringsOf(context).ticketWalletPay,
  TicketState.done || TicketState.voided => '',
};

String walletNotice(BuildContext context, MyRegistration ticket) =>
    switch (ticket.registrationStatus) {
      4 => stringsOf(context).ticketWalletExpiredNotice,
      3 => stringsOf(context).ticketWalletCancelledNotice,
      _ => stringsOf(context).ticketWalletUnknownNotice,
    };
