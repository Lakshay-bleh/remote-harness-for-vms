import '../../core/api.dart';
import 'autopilot_models.dart';

/// Autopilot over the Escanor API (the website's Automations page uses the same calls).
extension AutopilotApi on Api {
  Future<AutopilotOverview> autopilotOverview() async => AutopilotOverview.fromJson(await get('/autopilot'));

  Future<AutopilotPolicy> setAutopilotPolicy(Map<String, Object?> change) async => AutopilotPolicy.fromJson(await request('PUT', '/autopilot/policy', body: change));

  Future<void> pauseAutopilot() async => post('/autopilot/pause');

  Future<void> resumeAutopilot() async => post('/autopilot/resume');

  Future<AutopilotRun> startAutopilotRun(String goal, {String criteria = ''}) async =>
      AutopilotRun.fromJson(await post('/autopilot/runs', {'goal': goal, 'criteria': criteria}));

  Future<AutopilotRun> autopilotRun(String id) async => AutopilotRun.fromJson(await get('/autopilot/runs/${enc(id)}'));

  Future<void> stopAutopilotRun(String id) async => post('/autopilot/runs/${enc(id)}/stop');

  Future<void> answerAutopilotRun(String id, {required bool allow}) async => post('/autopilot/runs/${enc(id)}/${allow ? 'approve' : 'deny'}');

  Future<Trigger> addTrigger(Map<String, Object?> body) async => Trigger.fromJson(await post('/autopilot/triggers', body));

  Future<Trigger> editTrigger(String id, Map<String, Object?> body) async => Trigger.fromJson(await patch('/autopilot/triggers/${enc(id)}', body));

  Future<void> removeTrigger(String id) async => delete('/autopilot/triggers/${enc(id)}');

  Future<AutopilotRun> runTriggerNow(String id) async => AutopilotRun.fromJson(await post('/autopilot/triggers/${enc(id)}/run'));
}
