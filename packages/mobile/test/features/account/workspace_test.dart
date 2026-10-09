import 'package:escanor/features/account/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

// Port of packages/web/src/escanor/account/workspace.test.ts.
void main() {
  group('workspace', () {
    test('cleans a name to one line of 1 to 80 characters, or refuses it', () {
      expect(cleanWorkspaceName('  My   team \n space '), 'My team space');
      expect(cleanWorkspaceName('   '), null);
      expect(cleanWorkspaceName('x' * 81), null);
      expect(cleanWorkspaceName('x' * 80)?.length, 80);
    });
    test('labels regions, environments and roles, and leaves unknown ones as they are', () {
      expect(regionLabel('ap-south'), 'India and South Asia');
      expect(regionLabel('mars'), 'mars');
      expect(environmentLabel('staging'), 'Staging');
      expect(roleLabel('owner') + roleLabel('admin') + roleLabel('x'), 'OwnerAdminMember');
    });
    test('turns an audit action into a sentence', () {
      expect(describeAction('workspace.settings_updated'), 'Workspace settings updated');
      expect(describeAction('billing.plan_changed'), 'Billing plan changed');
      expect(describeAction(''), 'Activity');
    });
  });

  group('activity paging and filters', () {
    AuditLine line(String action, [String actor = 'a@x.io', String target = '', String detail = '']) =>
        AuditLine(action: action, actorEmail: actor, target: target, detail: detail);
    final lines = [line('billing.plan_changed', 'a@x.io', 'pro'), line('member.role_changed', 'b@x.io', 'carol'), line('billing.cancel_requested'), line('integration.connected', 'a@x.io', 'github')];
    test('groups by the kind before the dot, most frequent first', () {
      expect(activityGroups(lines).map((g) => [g.value, g.count]).toList(), [
        ['billing', 2],
        ['integration', 1],
        ['member', 1],
      ]);
      expect(activityGroups(lines).first.label, 'Billing');
    });
    test('filters by kind and by any word in the line', () {
      expect(filterActivity(lines, group: 'billing').length, 2);
      expect(filterActivity(lines, query: 'CAROL').length, 1);
      expect(filterActivity(lines, group: 'billing', query: 'carol').length, 0);
      expect(filterActivity(lines, query: 'plan changed').length, 1);
    });
    test('offers more only while the last answer was full and the ceiling is not reached', () {
      expect(canLoadMore(25, 25), true);
      expect(canLoadMore(12, 25), false);
      expect(canLoadMore(activityMax, activityMax), false);
      expect(nextActivityLimit(25), 75);
      expect(nextActivityLimit(480), activityMax);
    });
    test('reads the team, and an action with no dot is its own kind', () {
      final org = Organization.fromJson({
        'your_role': 'owner',
        'members': [
          {'user_id': 'u1', 'email': 'a@x.io', 'name': 'Ada', 'role': 'owner'},
          {'user_id': 'u2', 'email': 'b@x.io', 'role': 'member'},
        ],
      });
      expect(org.members.map((m) => m.role), ['owner', 'member']);
      expect(actionGroup('login'), 'login');
      expect(actionGroup('.x'), 'other');
    });
  });
}
