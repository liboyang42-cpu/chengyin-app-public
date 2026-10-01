import '../../data/api/coupon_api.dart';
import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';

/// Translates known local type/status/validation helpers only, never backend text.
String merchantCouponLocalText(BuildContext context, String text) => switch (text) {
  '优惠券' => stringsOf(context).merchantCouponCoupons,
  '请选择' => stringsOf(context).merchantCouponSelect,
  '礼品券' => stringsOf(context).merchantCouponGift,
  '9折券' => stringsOf(context).merchantCouponDiscountTen,
  '8折券' => stringsOf(context).merchantCouponDiscountTwenty,
  '体验卡' => stringsOf(context).merchantCouponTrial,
  '请输入优惠券名称' => stringsOf(context).merchantCouponEnterName,
  '请选择优惠券日期' => stringsOf(context).merchantCouponSelectDates,
  '请选择优惠券类型' => stringsOf(context).merchantCouponSelectType,
  '请输入大于0的投放数量' => stringsOf(context).merchantCouponPositiveQuantity,
  '结束时间要晚于开始时间' => stringsOf(context).merchantCouponDateOrder,
  '未开始' => stringsOf(context).merchantCouponNotStarted,
  '进行中' => stringsOf(context).merchantCouponOngoing,
  '已结束' => stringsOf(context).merchantCouponEnded,
  '已失效' => stringsOf(context).merchantCouponInvalid,
  '已停发' => stringsOf(context).merchantCouponStopped,
  _ => text,
};

String couponLocalFailureText(BuildContext context, CouponLocalFailure error) =>
    switch (error.kind) {
      CouponLocalFailureKind.load => stringsOf(context).merchantCouponLoadFailed,
      CouponLocalFailureKind.publish => stringsOf(context).merchantCouponPublishFailed,
      CouponLocalFailureKind.stop => stringsOf(context).merchantCouponStopFailed,
    };
