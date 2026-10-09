import 'package:escanor/features/voice/commands.dart';
import 'package:flutter_test/flutter_test.dart';

const ctx = VoiceContext(hasComputer: true);

PhoneAction? act(String say) {
  final c = parseVoiceCommand(say, ctx);
  return c is PhoneCommand ? c.action : null;
}

void main() {
  group('wake phrase and the name', () {
    test('strips "hey escanor" however it was heard', () {
      for (final said in ['hey escanor open youtube', 'Hey Escaner, open youtube', 'ok es canor open youtube', 'hey ex canor open youtube']) {
        expect(stripWake(said), 'open youtube', reason: said);
      }
    });
    test('leaves ordinary sentences alone', () {
      expect(stripWake('open the scanner app'), 'open the scanner app');
      expect(canonicalizeName('escalator'), 'escalator');
    });
  });

  group('phone actions', () {
    test('opens an app or a site by name', () {
      expect(parseVoiceCommand('open youtube', ctx), const PhoneCommand(OpenApp('youtube')));
      expect(parseVoiceCommand('Hey Escanor, launch WhatsApp', ctx), const PhoneCommand(OpenApp('whatsapp')));
      expect(parseVoiceCommand('start the camera', ctx), const PhoneCommand(OpenApp('camera')));
    });
    test('calls a number or a name', () {
      expect(parseVoiceCommand('call mom', ctx), const PhoneCommand(Call('mom')));
      expect(parseVoiceCommand('call 98765 43210', ctx), const PhoneCommand(Call('9876543210')));
    });
    test('sets alarms and timers', () {
      expect(parseVoiceCommand('set an alarm for 7:30 am', ctx), const PhoneCommand(SetAlarm(7, 30)));
      expect(parseVoiceCommand('wake me up at 6 pm', ctx), const PhoneCommand(SetAlarm(18, 0)));
      expect(parseVoiceCommand('set a timer for 5 minutes', ctx), const PhoneCommand(SetTimer(300)));
      expect(parseVoiceCommand('timer 1 hour 30 minutes', ctx), const PhoneCommand(SetTimer(5400)));
    });
    test('controls the torch and the volume', () {
      expect(parseVoiceCommand('turn on the flashlight', ctx), const PhoneCommand(Torch(true)));
      expect(parseVoiceCommand('torch off', ctx), const PhoneCommand(Torch(false)));
      expect(parseVoiceCommand('volume up', ctx), const PhoneCommand(Volume(VolumeChange.up)));
      expect(parseVoiceCommand('mute', ctx), const PhoneCommand(Volume(VolumeChange.mute)));
    });
    test('searches the web and opens a settings screen', () {
      expect(parseVoiceCommand('search for best pizza near me', ctx), const PhoneCommand(WebSearch('best pizza near me')));
      expect(parseVoiceCommand('open wifi settings', ctx), const PhoneCommand(OpenSettings(SettingsScreen.wifi)));
      expect(parseVoiceCommand('open bluetooth settings', ctx), const PhoneCommand(OpenSettings(SettingsScreen.bluetooth)));
    });
  });

  group('using the phone itself', () {
    test('presses the phone’s buttons', () {
      expect(act('go home'), const Control(ControlOp.home));
      expect(act('go to the home screen'), const Control(ControlOp.home));
      expect(act('go back'), const Control(ControlOp.back));
      expect(act('show recent apps'), const Control(ControlOp.recents));
      expect(act('open notifications'), const Control(ControlOp.notifications));
      expect(act('quick settings'), const Control(ControlOp.quickSettings));
      expect(act('lock the phone'), const Control(ControlOp.lock));
      expect(act('take a screenshot'), const Control(ControlOp.screenshot));
      expect(act('scroll down'), const Control(ControlOp.scrollDown));
      expect(act('scroll up'), const Control(ControlOp.scrollUp));
    });
    test('taps what is on the screen by its words, and types', () {
      expect(act('tap Send'), const TapText('send'));
      expect(act('click on the sign in button'), const TapText('sign in'));
      expect(act('type hello there'), const TypeText('hello there'));
    });
    test('keeps the case of what is typed', () {
      expect(act('type Meet me at 5 PM.'), const TypeText('Meet me at 5 PM'));
    });
    test('reads the screen only when asked', () {
      expect(act('what is on my screen'), const ReadScreen());
      expect(act('read the screen'), const ReadScreen());
    });
    test('opens a website by its address, however the dots were heard', () {
      expect(act('go to google.com'), const OpenUrl('https://google.com'));
      expect(act('open github dot com'), const OpenUrl('https://github.com'));
    });
    test('does not mistake an app name or a question for any of these', () {
      expect(act('open youtube'), const OpenApp('youtube'));
      expect(act('why is the build back to failing'), isNull);
    });
    test('searches for what was said, not for the word google', () {
      expect(act('search google for cats'), const WebSearch('cats'));
      expect(act('google best pizza near me'), const WebSearch('best pizza near me'));
    });
    test('names the control ops the way the native side does', () {
      expect(controlOpName(ControlOp.quickSettings), 'quick_settings');
      expect(controlOpName(ControlOp.scrollDown), 'scroll_down');
      expect(controlOpName(ControlOp.home), 'home');
    });
  });

  group('the computer', () {
    test('goes to the computer when asked to, and sends the rest of the sentence', () {
      expect(parseVoiceCommand('on my computer open youtube', ctx), const ComputerCommand('open youtube'));
      expect(parseVoiceCommand('tell my laptop to show my containers', ctx), const ComputerCommand('show my containers'));
      expect(parseVoiceCommand('ask my pc what is using my memory', ctx), const ComputerCommand('what is using my memory'));
      expect(parseVoiceCommand('open youtube on my computer', ctx), const ComputerCommand('open youtube'));
    });
    test('says there is no computer to ask when none is paired, instead of guessing', () {
      expect(parseVoiceCommand('on my computer open youtube', const VoiceContext(hasComputer: false)), const NoComputerCommand('open youtube'));
    });
  });

  group('everything else', () {
    test('goes to the assistant', () {
      expect(parseVoiceCommand('why is checkout slow', ctx), const AssistantCommand('why is checkout slow'));
      expect(parseVoiceCommand('hey escanor what needs my attention', ctx), const AssistantCommand('what needs my attention'));
    });
    test('moves around the app', () {
      expect(parseVoiceCommand('go to my computers', ctx), const GoCommand(VoiceTab.computers));
      expect(parseVoiceCommand('show settings', ctx), const GoCommand(VoiceTab.settings));
      expect(parseVoiceCommand('open the chat', ctx), const GoCommand(VoiceTab.assistant));
    });
    test('stops on cancel, and ignores silence', () {
      for (final w in ['cancel', 'never mind', 'stop', 'forget it']) {
        expect(parseVoiceCommand(w, ctx), const StopCommand(), reason: w);
      }
      for (final w in ['', '   ', 'hey escanor']) {
        expect(parseVoiceCommand(w, ctx), const EmptyCommand(), reason: w);
      }
    });
  });

  group('parseClock', () {
    test('reads times people say', () {
      expect(parseClock('7 am'), (hour: 7, minute: 0));
      expect(parseClock('7:30 pm'), (hour: 19, minute: 30));
      expect(parseClock('12 am'), (hour: 0, minute: 0));
      expect(parseClock('12 pm'), (hour: 12, minute: 0));
      expect(parseClock('quarter past 6'), (hour: 6, minute: 15));
      expect(parseClock('18:45'), (hour: 18, minute: 45));
      expect(parseClock('half past 9 am'), (hour: 9, minute: 30));
    });
    test('refuses nonsense', () {
      for (final bad in ['', 'banana', '25 am', '7:75', '13 pm']) {
        expect(parseClock(bad), isNull, reason: bad);
      }
    });
  });

  group('parseDuration', () {
    test('adds up hours, minutes and seconds', () {
      expect(parseDuration('5 minutes'), 300);
      expect(parseDuration('1 hour 30 minutes'), 5400);
      expect(parseDuration('90 seconds'), 90);
      expect(parseDuration('half an hour'), 1800);
      expect(parseDuration('two minutes'), 120);
    });
    test('refuses nonsense and absurd lengths', () {
      expect(parseDuration('soon'), isNull);
      expect(parseDuration('0 minutes'), isNull);
      expect(parseDuration('9999 hours'), isNull);
    });
  });
}
