var app = angular.module('rdb', [])

app.controller('MainCtrl', function($scope, $http) {
  var self = this;

  $scope.process = null;
  $scope.running = true;
  $scope.activeThread = null;
  $scope.activeFrame = null;
  $scope.locals = {};
  self.liveThread = null;

  var source = new EventSource('/events');
  source.addEventListener('message', function(e) {
    $scope.$apply(function() {
      var message = JSON.parse(e.data);
      if (message.event == 'breakpoint') {
        updateThreads();
        updateRunning();
      }
    });
  }, false);

  $scope.showSettings = function() {
  };

  $scope.pause = function() {
    $http.put('/pause')
      .success(function(res) {
        $scope.running = res.running;
        updateThreads();
      });
  };

  $scope.resume = function() {
    $http.put('/resume')
      .success(function(res) {
        $scope.running = res.running;
      });
  };

  $scope.stepIn = function() {
    $http.put('/step-in')
      .success(function(res) {
        updateThreads();
        updateLocals();
      });
  };

  $scope.stepOver = function() {
    $http.put('/step-over')
      .success(function(res) {
        updateThreads();
        updateLocals();
      });
  };

  $scope.stepOut = function() {
    $http.put('/step-out')
      .success(function(res) {
        updateThreads();
        updateLocals();
      });
  };

  $scope.openFile = function(path, line) {
    $http.post('/open', { path: path, line: line })
      .success(function() {
      });
  }

  $scope.setActiveThread = function(thread) {
    $scope.activeThread = thread;
    $scope.setActiveFrame(thread.backtrace[0]);
  };
  
  $scope.setActiveFrame = function(frame) {
    $scope.activeFrame = frame;
  };

  function updateThreads() {
    $http.get('/threads')
      .success(function(res) {
        $scope.threads = res;

        for (var i = 0; i < $scope.threads.length; ++i) {
          var thread = $scope.threads[i];
          if (thread.main) {
            self.liveThread = thread;
            $scope.setActiveThread(self.liveThread);
            break;
          }
        }
      });
  }

  function updateLocals() {
    $http.get('/locals')
      .success(function(res) {
        $scope.locals = res;
      });
  }

  function updateRunning() {
    $http.get('/running')
      .success(function(res) {
        $scope.running = res.running;
      });
  }

  function connect() {
    $http.get('/process')
      .success(function(res) {
        $scope.process = res.process;
      });

    updateRunning();
    updateThreads();
    updateLocals();
  }

  connect();
});

app.controller('SourceEditCtrl', function($scope, $http) {
  var self = this;

  // Maps line number to breakpoint ID.
  self.breakpoints = {};
  self.activeLineMarker = null;
  self.activeGutterRow = null;

  self.editor = ace.edit('source-editor');
  self.editor.setTheme('ace/theme/clouds');
  self.editor.session.setMode("ace/mode/ruby");
  self.editor.setReadOnly(true); 
  self.editor.setShowPrintMargin(false);

  self.editor.on('guttermousedown', function(e) {
    if (e.domEvent.button != 0 /* left click */) {
      return;
    }

    var target = e.domEvent.target;
    if (target.className.indexOf('ace_gutter-cell') < 0) {
      return;
    }

    var row = e.getDocumentPosition().row;
    var line = row + 1;
    var breakpoints = e.editor.session.getBreakpoints();
    var exists = breakpoints[row] != null;

    if (exists) {
      removeBreakpoint(line);
    } else {
      addBreakpoint(line);
    }

    e.stop();
  });

  $scope.$watch('activeFrame', function(newFrame, oldFrame) {
    if (newFrame == null) {
      return;
    }

    if ((oldFrame == null) || (newFrame.path != oldFrame.path)) {
      // TODO: Avoid requesting source constantly if we already have it locally.
      // TODO: Cache source locally (in-mem, localStorage).
      $http.get('/source', { params: { path: newFrame.path } })
        .success(function(res) {
          $scope.currentSource = res;
          self.editor.setValue($scope.currentSource, newFrame.line);
          setActiveLine(newFrame.line);
        });
    } else {
      setActiveLine(newFrame.line);
    }
  });

  function setActiveLine(line) {
    if (!self.editor)
      return;

    setTimeout(function() {
      self.editor.scrollToLine(line, true, true, function() {});

      var lineText = self.editor.session.getLine(line - 1);
      var endCol = lineText.length;
      var startCol = 1;
      var match = /\S/.exec(lineText);
      if (match) {
        startCol = match.index;
      }

      if (self.activeLineMarker != null) {
        self.editor.session.removeMarker(self.activeLineMarker);
      }

      var row = line - 1;
      var aceRange = ace.require('ace/range').Range;
      var range = new aceRange(row, startCol, row, endCol);
      self.activeLineMarker = self.editor.session.addMarker(range, 'live-command', 'text');

      if (self.activeGutterRow != null) {
        self.editor.session.removeGutterDecoration(self.activeGutterRow, 'live-command');
      }

      self.activeGutterRow = row;
      self.editor.session.addGutterDecoration(self.activeGutterRow, 'live-command');
    }, 0);
  };

  function addBreakpoint(line) {
    var params = { file: $scope.activeFrame.path, line: line };
    $http.post('/breakpoints', params)
      .success(function(res) {
        var row = line - 1;
        self.editor.session.setBreakpoint(row);

        var breakpointId = res.id;
        self.breakpoints[line] = breakpointId;
      });
  }

  function removeBreakpoint(line) {
    var breakpointId = self.breakpoints[line];
    if (breakpointId == null) {
      return;
    }

    $http.delete('/breakpoints/' + breakpointId)
      .success(function(res) {
        var row = line - 1;
        self.editor.session.clearBreakpoint(row);

        delete self.breakpoints[line];
      });
  }

  function updateBreakpoints() {
    $http.get('/breakpoints')
      .success(function(res) {
        for (var i = 0; i < res.length; ++i) {
          var breakpoint = res[i];
          var row = breakpoint.line - 1;
          self.editor.session.setBreakpoint(row);
          self.breakpoints[breakpoint.line] = breakpoint.id;
        }
      });
  }

  updateBreakpoints();
});

app.controller('ExpressionEditCtrl', function($scope, $http) {
  // TODO: Should be a directive?
  var editor = ace.edit('expr-editor');
  editor.renderer.setShowGutter(false);
  editor.renderer.setShowPrintMargin(false);
  editor.setValue('> ');
  editor.navigateLineEnd();
  editor.navigateRight(1);
  editor.session.setUseWrapMode(true);

  editor.keyBinding.realOnCommandKey = editor.keyBinding.onCommandKey;
  editor.keyBinding.onCommandKey = function(e, hashId, keyCode) {
    if (e.ctrlKey && (keyCode == 76)) {
      editor.setValue('> ');
      editor.navigateLineEnd();
      editor.navigateRight(1);
      e.preventDefault();
    } else if (keyCode == 13) { 
      var lineNumber = editor.selection.getCursor().row;
      var line = editor.session.getLine(lineNumber);
      var match = /\s*>\s*(.*)/.exec(line);
      if (match) {
        var expr = match[1];
        var params = { expr: match[1], frame: getFrameIndex($scope.activeFrame) };
        $http.put('/eval', params)
          .success(function(res) {
            var result = res.success || res.failure;
            editor.insert(result);
            editor.insert('\n> ');
          });
      }
    } else {
      this.realOnCommandKey(e, hashId, keyCode);
    }
  }

  function getFrameIndex(frame) {
    var frames = $scope.activeThread.backtrace;
    for (var i = 0; i < frames.length; ++i) {
      if (frames[i] == frame) {
        return i;
      }
    }

    return null;
  }
});
