var app = angular.module('rdb', ['ngTable'])

function Events(url) {
  this.source = new EventSource(url);
  this.handlers = {};
  var self = this;

  this.source.addEventListener('message', function(e) {
    var message = JSON.parse(e.data);
    var handlers = self.handlers[message.event];
    if (handlers) {
      for (var i = 0; i < handlers.length; ++i) {
        handlers[i](message);
      }
    }
  }, false);

  this.on = function(eventName, handler) {
    if (typeof eventName == 'string') {
      this.handlers[eventName] = this.handlers[eventName] || [];
      this.handlers[eventName].push(handler);
    } else if (eventName instanceof Array) {
      var names = eventName;
      for (var i = 0; i < names.length; ++i) {
        this.on(names[i], handler);
      }
    }
  };
}

app.controller('MainCtrl', function($scope, $http) {
  var self = this;

  $scope.process = null;
  $scope.running = true;
  $scope.activeThread = null;
  $scope.activeFrame = null;
  $scope.locals = {};
  self.liveThread = null;

  $scope.events = new Events('/events');
  $scope.events.on('break', function() {
    $scope.$apply(function() {
      updateThreads();
      updateRunning();
    });
  });

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
    $http.post('/edit', { path: path, line: line })
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
  self.editor = null;

  function setupEditor() {
    var editor = ace.edit('source-editor');
    editor.setTheme('ace/theme/clouds');
    editor.session.setMode("ace/mode/ruby");
    editor.setReadOnly(true); 
    editor.setShowPrintMargin(false);

    editor.on('guttermousedown', function(e) {
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

    self.editor = editor;
  }

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
        for (var line in self.breakpoints) {
          var row = line - 1;
          self.editor.session.clearBreakpoint(row);
        }

        self.breakpoints = {};

        for (var i = 0; i < res.length; ++i) {
          var breakpoint = res[i];
          var row = breakpoint.line - 1;
          self.editor.session.setBreakpoint(row);
          self.breakpoints[breakpoint.line] = breakpoint.id;
        }
      });
  }

  $scope.events.on(['breakpoint-created', 'breakpoint-deleted'], function(e) {
    $scope.$apply(function() {
      updateBreakpoints();
    });
  });

  updateBreakpoints();
  setTimeout(setupEditor, 0);
});

app.controller('ExpressionEditCtrl', function($scope, $http) {
  var self = this;
  self.editor = null;

  function setupEditor() {
    // TODO: Should be a directive?
    var editor = ace.edit('expr-editor');
    editor.renderer.setShowGutter(false);
    editor.renderer.setShowPrintMargin(false);
    editor.setValue('> ');
    editor.navigateLineEnd();
    editor.navigateRight(1);
    editor.session.setUseWrapMode(true);

    editor.commands.addCommand({
      name: 'Clear',
      bindKey: { win: 'Ctrl-L',  mac: 'Command-L' },
      exec: function(editor) {
        editor.setValue('> ');
        editor.navigateLineEnd();
        editor.navigateRight(1);
        return true;
      }
    });

    editor.commands.addCommand({
      name: 'Evaluate',
      bindKey: { win: 'Enter',  mac: 'Enter' },
      exec: function(editor) {
        var lineNumber = editor.selection.getCursor().row;
        var line = editor.session.getLine(lineNumber);
        var match = /\s*>\s*(.*)/.exec(line);
        if (match) {
          var expr = match[1];
          var params = { expr: match[1], frame: getFrameIndex($scope.activeFrame) };
          $http.put('/eval', params)
            .success(function(res) {
              editor.insert('\n');
              editor.insert(JSON.stringify(res));
              editor.insert('\n> ');
            });
        }
        return true;
      }
    });

    self.editor = editor;
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

  setTimeout(setupEditor, 0);
});

app.controller('EnvironmentCtrl', function($scope, ngTableParams) {
  $scope.tableParams = new ngTableParams({
      count: 0
    }, {
      counts: []
    });

  $scope.$watch('process', function(newProcess, _) {
    if (newProcess == null) {
      return;
    }

    $scope.tableParams = new ngTableParams({
      count: Object.keys(newProcess.env).length
    }, {
      counts: [],
      total: Object.keys(newProcess.env).length,
      getData: function($defer, params) {
        $defer.resolve(newProcess.env)
      }
    });

    // See https://github.com/esvit/ng-table/issues/297
    $scope.tableParams.settings().$scope = $scope;
    $scope.tableParams.reload();
  });
});
