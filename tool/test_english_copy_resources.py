"""Regression gates for reviewed copy; does not evaluate Flutter ICU output."""
import json
from pathlib import Path
import re
import unittest


class ReviewedEnglishCopyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.en = json.loads((root / 'lib/l10n/app_en.arb').read_text())
        cls.zh = json.loads((root / 'lib/l10n/app_zh.arb').read_text())

    def test_each_reviewed_integer_counter_has_its_own_plural_branch(self):
        counters = {
            'roamLiveTripsCount': ['count'], 'roamLiveStampsCount': ['count'],
            'roamLiveRunnerCount': ['count'], 'roamLiveRunnersArea': ['count'],
            'roamLiveHangoutMembers': ['count'], 'mapLandingNodeCount': ['count'],
            'objectCardsPile': ['count'],
            **{key: ['count'] for key in [
                'officialOperatorReachCount', 'officialPlayerParticipants',
                'officialPlayerDays', 'officialPlayerHours', 'officialPlayerCountdownDays',
                'officialPlayerCountdownHours', 'officialPlayerCountdownMinutes', 'clubTopicFailedSessions']},
            'profilePostCounts': ['likes', 'comments'],
            'roamLiveProgress': ['tiles', 'shops'], 'roamLiveRunnerStats': ['shops'],
        }
        for key, fields in counters.items():
            for field in fields:
                with self.subTest(key=key, field=field):
                    self.assertEqual(self.zh['@' + key]['placeholders'][field]['type'], 'int')
                    self.assertRegex(self.en[key], r'\{' + field + r',\s*plural,')
                    self.assertIn('other{', self.en[key])

    def test_fog_is_cleared_not_revealed(self):
        for key in ['roamLiveLocationPurpose', 'roamLiveRuleExploreBody', 'roamLiveFreeRoamBody']:
            self.assertIn('clear the fog', self.en[key].lower())
            self.assertNotRegex(self.en[key].lower(), r'reveal(?: the)? fog')

    def test_ticket_and_badge_terminology_is_consistent(self):
        for key in ['registrationOrdersFreeTicketHint', 'registrationOrdersPaidTicketHint']:
            self.assertIn('Tickets', self.en[key])
            self.assertNotIn('wallet', self.en[key].lower())
        for key in ['profileBadges', 'profileBadgesDetail', 'profileBadgesEmpty',
                    'profileBadgesEmptyDetail', 'profileMedalCount', 'profileBenefitMedal']:
            self.assertIn('badge', self.en[key].lower())
            self.assertNotIn('medal', self.en[key].lower())
        self.assertEqual(self.en['profileBecomeLeader'], 'Become a club organizer')

    def test_redemption_is_distinct_from_attendance(self):
        self.assertEqual(self.en['clubCheckinTitle'], 'Redemption details')
        self.assertEqual(self.en['clubCheckinVerifiedTime'], 'Redemption time')
        for prefix in ['clubEnroll', 'clubCustomer', 'clubTopic']:
            self.assertEqual(self.en[prefix + 'Verified'], 'Redeemed')
            self.assertEqual(self.en[prefix + 'Pending'], 'Awaiting redemption')
        self.assertIn('redeemed tickets', self.en['clubTopicManualRefundBody'])
        self.assertIn('unredeemed tickets', self.en['clubTopicEndRefundBody'])
        self.assertEqual(self.en['officialOperatorCompleteCount'], 'Participants who completed')
        self.assertEqual(self.en['officialOperatorSignupCount'], 'Registered participants')
        self.assertEqual(self.en['clubRolesOwner'], 'Club organizer')
        self.assertEqual(self.en['merchantOperationsOrderCount'], 'Orders: {count}')
        self.assertEqual(self.en['merchantOperationsAdjustmentCount'], 'Pending adjustments: {count}')

    def test_string_counts_are_not_coerced_and_yuan_is_not_changed_to_dollars(self):
        self.assertEqual(self.zh['@registrationOrdersMinutes']['placeholders']['duration']['type'], 'String')
        self.assertEqual(self.zh['@registrationOrdersPlayerCount']['placeholders']['count']['type'], 'String')
        self.assertEqual(self.en['registrationOrdersMinutes'], '{duration} min')
        self.assertEqual(self.en['registrationOrdersPlayerCount'], 'Players: {count}')
        self.assertIn('¥{amount}', self.en['registrationOrdersPointsAmount'])
        self.assertNotRegex(self.en['registrationOrdersPointsAmount'], r'USD|\$')


if __name__ == '__main__':
    unittest.main()
