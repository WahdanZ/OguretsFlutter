part of ogurets_flutter;

// this is taken from the gherkin package and then modified. https://github.com/jonsamwell/dart_gherkin

class FlutterRunProcessHandler {
  static const String FAIL_COLOUR = "\u001b[33;31m"; // red
  static const String RESET_COLOUR = "\u001b[33;0m";

  static RegExp _observatoryDebuggerUriRegex = RegExp(
      r"observatory debugger .*[:]? (http[s]?:.*\/).*",
      caseSensitive: false,
      multiLine: false);

  static RegExp _restartedApplicationSuccess = RegExp(
      r"Restarted application (.*)ms.",
      caseSensitive: false,
      multiLine: false);

  static RegExp _noConnectedDeviceRegex =
      RegExp(r"no connected device", caseSensitive: false, multiLine: false);

  static RegExp _usageRegex =
    RegExp(r"Usage: flutter run \[arguments\]", caseSensitive: false, multiLine: false);

  static RegExp _finished =
      RegExp(r"Application (.*)\.", caseSensitive: false, multiLine: false);

  Process _runningProcess;
  Stream<String> _processStdoutStream;
  List<StreamSubscription> _openSubscriptions = <StreamSubscription>[];
  final String _appTarget;
  final String _workingDirectory;
  String deviceId;
  String flavour;
  String observatoryPort = '8888';
  String additionalArguments;

  FlutterRunProcessHandler(this._appTarget, this._workingDirectory, {this.flavour, this.deviceId, this.observatoryPort, this.additionalArguments});

  Future<void> run() async {
    List<String> cmdLine = ["run", "--target=$_appTarget", "--observatory-port", observatoryPort];
    
    if (flavour != null) {
      cmdLine.addAll(["--flavor", flavour]);
    }
    
    if (deviceId != null) {
      cmdLine.addAll(["-d", deviceId]);
    }
    
    if (additionalArguments != null) {
      cmdLine.addAll(split(additionalArguments));
    }

    _log.info("flutter ${cmdLine.join(' ')}");

    _runningProcess = await Process.start("flutter",
        cmdLine,
        workingDirectory: _workingDirectory, runInShell: true);
    _processStdoutStream =
        _runningProcess.stdout.transform(utf8.decoder).asBroadcastStream();

    _openSubscriptions.add(_runningProcess.stderr.listen((events) {
      stderr.writeln(
          "${FAIL_COLOUR}Flutter run error: ${String.fromCharCodes(events)}$RESET_COLOUR");
    }));
  }

  // attempts to restart the running app
  Future restart() async {
    if (_runningProcess != null) {
      _runningProcess.stdin.write("R");
      return waitForConsoleMessage(
          _restartedApplicationSuccess,
          "Timeout waiting for app restart",
          "${FAIL_COLOUR}No connected devices found to run app on and tests against$RESET_COLOUR");
    }
  }

  Future<int> terminate() async {
    print("closing app.");
    int exitCode = -1;
    _ensureRunningProcess();
    if (_runningProcess != null) {
      _runningProcess.stdin.write("q");
      _openSubscriptions.forEach((s) => s.cancel());
      _openSubscriptions.clear();
      await waitForConsoleMessage(_finished, "Application not finished!!!", "");
      exitCode = await _runningProcess.exitCode;
      _runningProcess = null;
    }

    return exitCode;
  }

  Future<String> waitForConsoleMessage(
      RegExp search, String timeoutException, String failMessage,
      [Duration timeout = const Duration(seconds: 60)]) {
    _ensureRunningProcess();
    final completer = Completer<String>();
    StreamSubscription sub;

    Timer timer;

    sub = _processStdoutStream.listen((logLine) {
      stdout.write(">> ${logLine}");
      if (search.hasMatch(logLine)) {
        timer?.cancel();
        sub?.cancel();
        if (!completer.isCompleted) {
          completer.complete(search.firstMatch(logLine).group(1));
        }
      } else if (_noConnectedDeviceRegex.hasMatch(logLine)) {
        timer?.cancel();
        sub?.cancel();
        if (!completer.isCompleted) {
          stderr.writeln(failMessage);
          completer.completeError(
              new Exception("no device running to test against"));
        }
      } else if (_usageRegex.hasMatch(logLine)) {
        timer?.cancel();
        sub?.cancel();
        if (!completer.isCompleted) {
          stderr.writeln("${FAIL_COLOUR}Incorrect parameters for flutter run. Please check the command line above and resolve any issues.$RESET_COLOUR");
          completer.completeError(
              new Exception("incorrect parameters for flutter run."));
        }
      }
    }, cancelOnError: true);

    timer = new Timer(timeout, () {
      sub?.cancel();
      if (!completer.isCompleted) {
        stderr.writeln("timed out");
        completer.completeError(new Exception("timed out"));
      }
    });

    return completer.future;
  }

  Future<String> waitForObservatoryDebuggerUri(
      [Duration timeout = const Duration(seconds: 60)]) {
    return waitForConsoleMessage(
        _observatoryDebuggerUriRegex,
        "Timeout while wait for observatory debugger uri",
        "${FAIL_COLOUR}No connected devices found to run app on and tests against$RESET_COLOUR");
  }

  void _ensureRunningProcess() {
    if (_runningProcess == null) {
      throw Exception(
          "FlutterRunProcessHandler: flutter run process is not active");
    }
  }
}
