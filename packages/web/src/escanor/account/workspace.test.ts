import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ACTIVITY_MAX, activityGroups, canLoadMore, cleanWorkspaceName, describeAction, filterActivity, nextActivityLimit, environmentLabel, regionLabel, roleLabel } from './workspace';

describe('workspace', () => {
  it('cleans a name to one line of 1 to 80 characters, or refuses it', () => {
    assert.equal(cleanWorkspaceName('  My   team \n space '), 'My team space');
    assert.equal(cleanWorkspaceName('   '), null);
    assert.equal(cleanWorkspaceName('x'.repeat(81)), null);
    assert.equal(cleanWorkspaceName('x'.repeat(80))?.length, 80);
  });
  it('labels regions, environments and roles, and leaves unknown ones as they are', () => {
    assert.equal(regionLabel('ap-south'), 'India and South Asia');
    assert.equal(regionLabel('mars'), 'mars');
    assert.equal(environmentLabel('staging'), 'Staging');
    assert.equal(roleLabel('owner') + roleLabel('admin') + roleLabel('x'), 'OwnerAdminMember');
  });
  it('turns an audit action into a sentence', () => {
    assert.equal(describeAction('workspace.settings_updated'), 'Workspace settings updated');
    assert.equal(describeAction('billing.plan_changed'), 'Billing plan changed');
    assert.equal(describeAction(''), 'Activity');
  });
});

describe('activity paging and filters', () => {
  const line = (action: string, actor = 'a@x.io', target = '', detail = '') => ({ action, actor_email: actor, target, detail });
  const lines = [line('billing.plan_changed', 'a@x.io', 'pro'), line('member.role_changed', 'b@x.io', 'carol'), line('billing.cancel_requested'), line('integration.connected', 'a@x.io', 'github')];
  it('groups by the kind before the dot, most frequent first', () => {
    assert.deepEqual(activityGroups(lines).map((g) => [g.value, g.count]), [['billing', 2], ['integration', 1], ['member', 1]]);
  });
  it('filters by kind and by any word in the line', () => {
    assert.equal(filterActivity(lines, { group: 'billing', query: '' }).length, 2);
    assert.equal(filterActivity(lines, { group: null, query: 'CAROL' }).length, 1);
    assert.equal(filterActivity(lines, { group: 'billing', query: 'carol' }).length, 0);
    assert.equal(filterActivity(lines, { group: null, query: 'plan changed' }).length, 1);
  });
  it('offers more only while the last answer was full and the ceiling is not reached', () => {
    assert.equal(canLoadMore(25, 25), true);
    assert.equal(canLoadMore(12, 25), false);
    assert.equal(canLoadMore(ACTIVITY_MAX, ACTIVITY_MAX), false);
    assert.equal(nextActivityLimit(25), 75);
    assert.equal(nextActivityLimit(480), ACTIVITY_MAX);
  });
});
