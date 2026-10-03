import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { cleanWorkspaceName, describeAction, environmentLabel, regionLabel, roleLabel } from './workspace';

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
