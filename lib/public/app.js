var app = angular.module('rdb', [])

app.controller('MainCtrl', function($scope, $http) {
  $scope.process = null;
  $scope.running = true;
  $scope.activeThread = null;
  $scope.activeFrame = null;
  $scope.currentSource = null;
  $scope.currentLine = null;
  $scope.locals = {};
  var currentMarker = null;
  var sourceEditor = null;
  var exprEditor = null;
  var self = this;

  var exprEditor = ace.edit('expr-editor');
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
      var line = exprEditor.getSession().getLine(lineNumber);
      var match = /\s*>\s*(.*)/.exec(line);
      if (match) {
        var expr = match[1];
        var params = { expr: match[1], frame: getFrameIndex($scope.activeFrame) };
        $http.get('/eval', { params: params })
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
    }
  });

  $scope.$watch('activeFrame', function(newFrame, _) {
    if (newFrame != null) {
      $http.get('/source', { params: { path: newFrame.path } })
        .success(function(res) {
          self.sourceEditor = ace.edit('source-editor');
          self.sourceEditor.setTheme('ace/theme/clouds');
          $scope.currentSource = res;
          updateLine();
        });
    }
  });

  $scope.$watch('currentSource', function(newSource, _) {
    if (newSource != null) {
      self.sourceEditor.getSession().setMode("ace/mode/ruby");
      self.sourceEditor.setReadOnly(true); 
      self.sourceEditor.setValue(newSource, 100);

      updateLine();
    }
  });

  function updateLine() {
    if (!self.sourceEditor)
      return;

    setTimeout(function() {
      var line = $scope.activeFrame.line;
      self.sourceEditor.resize(true);
      self.sourceEditor.scrollToLine(line, true, true, function() {});
      //self.sourceEditor.gotoLine(line, 0, false);

      var lineText = self.sourceEditor.getSession().getLine(line - 1);
      var endCol = lineText.length;
      var startCol = 1;
      var match = /\S/.exec(lineText);
      if (match) {
        startCol = match.index;
      }

      if (self.currentMarker != null) {
        self.sourceEditor.getSession().removeMarker(self.currentMarker);
      }

      var aceRange = ace.require('ace/range').Range;
      var range = new aceRange(line - 1, startCol, line - 1, endCol);
      self.currentMarker = self.sourceEditor.getSession().addMarker(range, 'active-command', 'text');
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
  
  $scope.setActiveFrame = function(frame) {
    $scope.activeFrame = frame;
  };

  function updateThreads() {
    $http.get('/threads')
      .success(function(res) {
        $scope.threads = res;

        for (var i = 0; i < $scope.threads.length; ++i) {
          if ($scope.threads[i].main) {
            $scope.activeThread = $scope.threads[i];
            updateLine();
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
});
