var app = angular.module('rdb', [])

app.controller('MainCtrl', function($scope, $http) {
  $scope.process = null;
  $scope.running = true;
  $scope.activeThread = null;
  $scope.activeFrame = null;
  $scope.currentSource = null;
  $scope.currentLine = null;
  $scope.isCurrent = true;
  $scope.locals = {};
  var breakThread = null;
  var currentMarker = null;
  var sourceEditor = null;
  var exprEditor = null;
  var self = this;

  // Maps line number to breakpoint ID.
  self.breakpoints = {};

  var exprEditor = ace.edit('expr-editor');
  exprEditor.renderer.setShowGutter(false);
  exprEditor.renderer.setShowPrintMargin(false);
  exprEditor.setValue('> ');
  exprEditor.navigateLineEnd();
  exprEditor.navigateRight(1);
  exprEditor.session.setUseWrapMode(true);

  exprEditor.keyBinding.origOnCommandKey = exprEditor.keyBinding.onCommandKey;
  exprEditor.keyBinding.onCommandKey = function(e, hashId, keyCode) {
    if (e.ctrlKey && (keyCode == 76)) {
      exprEditor.setValue('> ');
      exprEditor.navigateLineEnd();
      exprEditor.navigateRight(1);
      e.preventDefault();
    } else if (keyCode == 13) { 
      var lineNumber = exprEditor.selection.getCursor().row;
      var line = exprEditor.session.getLine(lineNumber);
      var match = /\s*>\s*(.*)/.exec(line);
      if (match) {
        var expr = match[1];
        var params = { expr: match[1], frame: getFrameIndex($scope.activeFrame) };
        $http.put('/eval', params)
          .success(function(res) {
            var result = res.success || res.failure;
            exprEditor.insert(result);
            exprEditor.insert('\n> ');
          });
      }
    } else {
      this.origOnCommandKey(e, hashId, keyCode);
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

  $scope.$watch('activeThread', function(newThread, _) {
    if (newThread != null) {
      $scope.activeFrame = newThread.backtrace[0];
      updateIsCurrent();
    }
  });

  function createSourceEditor(elementId) {
    var editor = ace.edit(elementId);
    editor.setTheme('ace/theme/clouds');
    editor.setShowPrintMargin(false);
    editor.on('guttermousedown', function(e) {
      var target = e.domEvent.target;

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

    return editor;
  }

  function addBreakpoint(line) {
    var params = { file: $scope.activeFrame.path, line: line };
    $http.post('/breakpoints', params)
      .success(function(res) {
        var row = line - 1;
        self.sourceEditor.session.setBreakpoint(row);

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
        self.sourceEditor.session.clearBreakpoint(row);

        delete breakpoints[line];
      });
  }

  $scope.$watch('activeFrame', function(newFrame, _) {
    if (newFrame != null) {
      $http.get('/source', { params: { path: newFrame.path } })
        .success(function(res) {
          $scope.currentSource = res;
          updateLine(false);
        });

      updateIsCurrent();
    }
  });

  function updateIsCurrent() {
    if ($scope.activeThread != self.breakThread) {
      $scope.isCurrent = false;
      return;
    }

    if ($scope.activeFrame != $scope.activeThread.backtrace[0]) {
      $scope.isCurrent = false;
      return;
    }

    $scope.isCurrent = true;
  }

  $scope.$watch('currentSource', function(newSource, _) {
    if (newSource != null) {
      self.sourceEditor.session.setMode("ace/mode/ruby");
      self.sourceEditor.setReadOnly(true); 
      self.sourceEditor.setValue(newSource, 100);

      updateLine(false);
    }
  });

  function updateLine(jumpToLine) {
    if (!self.sourceEditor)
      return;

    setTimeout(function() {
      var line = $scope.activeFrame.line;
      self.sourceEditor.scrollToLine(line, true, true, function() {});
      if (jumpToLine) {
        self.sourceEditor.gotoLine(line, 0, false);
      }

      var lineText = self.sourceEditor.session.getLine(line - 1);
      var endCol = lineText.length;
      var startCol = 1;
      var match = /\S/.exec(lineText);
      if (match) {
        startCol = match.index;
      }

      if (self.currentMarker != null) {
        self.sourceEditor.session.removeMarker(self.currentMarker);
      }

      var aceRange = ace.require('ace/range').Range;
      var range = new aceRange(line - 1, startCol, line - 1, endCol);
      self.currentMarker = self.sourceEditor.session.addMarker(range, 'active-command', 'text');
    }, 0);
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
    $http.put('/step_in')
      .success(function(res) {
        updateThreads();
        updateLocals();
      });
  };

  $scope.stepOver = function() {
    $http.put('/step_over')
      .success(function(res) {
        updateThreads();
        updateLocals();
      });
  };

  $scope.stepOut = function() {
    $http.put('/step_out')
      .success(function(res) {
        updateThreads();
        updateLocals();
      });
  };

  $scope.gotoCurrent = function() {
    $scope.activeThread = self.breakThread;
    $scope.activeFrame = $scope.activeThread.backtrace[0];
    updateLine(true);
  };
  
  $scope.setActiveFrame = function(frame) {
    $scope.activeFrame = frame;
  };

  $scope.openFile = function(path, line) {
    $http.post('/open', { path: path, line: line })
      .success(function() {
      });
  }

  function updateThreads() {
    $http.get('/threads')
      .success(function(res) {
        $scope.threads = res;

        for (var i = 0; i < $scope.threads.length; ++i) {
          if ($scope.threads[i].main) {
            $scope.activeThread = self.breakThread = $scope.threads[i];
            updateLine(false);
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

  function updateBreakpoints() {
    $http.get('/breakpoints')
      .success(function(res) {
        for (var i = 0; i < res.length; ++i) {
          var breakpoint = res[i];
          var row = breakpoint.line - 1;
          self.sourceEditor.session.setBreakpoint(row);
          self.breakpoints[breakpoint.line] = breakpoint.id;
        }
      });
  }

  $http.get('/process')
    .success(function(res) {
      $scope.process = res.process;
    });

  $http.get('/running')
    .success(function(res) {
      $scope.running = res.running;
    });

  updateThreads();
  updateLocals();
  updateBreakpoints();

  self.sourceEditor = createSourceEditor('source-editor');
});
