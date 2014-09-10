var app = angular.module('rdb', [])

app.controller('MainCtrl', function($scope, $http) {
  $scope.running = true;
  $scope.activeThread = null;
  $scope.activeFrame = null;
  $scope.currentSource = null;
  $scope.currentLine = null;
  $scope.expressionValue = null;
  $scope.locals = {};
  var currentMarker = null;
  var editor = null;
  var self = this;

  $scope.$watch('activeThread', function(newThread, _) {
    if (newThread != null) {
      $scope.activeFrame = newThread.backtrace[0];
    }
  });

  $scope.$watch('activeFrame', function(newFrame, _) {
    if (newFrame != null) {
      $http.get('/source', { params: { path: newFrame.path } })
        .success(function(res) {
          self.editor = ace.edit('editor');
          self.editor.setTheme('ace/theme/clouds');
          $scope.currentSource = res;
          updateLine();
        });
    }
  });

  $scope.$watch('currentSource', function(newSource, _) {
    if (newSource != null) {
      self.editor.getSession().setMode("ace/mode/ruby");
      self.editor.setReadOnly(true); 
      self.editor.setValue(newSource, 100);

      updateLine();
    }
  });

  $scope.evaluate = function(expr) {
    $http.get('/eval', { params: { expr: expr } })
      .success(function(res) {
        $scope.expressionValue = res.success || res.failure;
      });
  };

  function updateLine() {
    if (!self.editor)
      return;

    setTimeout(function() {
      var line = $scope.activeFrame.line;
      self.editor.resize(true);
      self.editor.scrollToLine(line, true, true, function() {});
      //self.editor.gotoLine(line, 0, false);

      var lineText = self.editor.getSession().getLine(line - 1);
      var endCol = lineText.length;
      var startCol = 1;
      var match = /\S/.exec(lineText);
      if (match) {
        startCol = match.index;
      }

      if (self.currentMarker != null) {
        self.editor.getSession().removeMarker(self.currentMarker);
      }

      var aceRange = ace.require('ace/range').Range;
      var range = new aceRange(line - 1, startCol, line - 1, endCol);
      self.currentMarker = self.editor.getSession().addMarker(range, 'active-command', 'text');
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

  $http.get('/running')
    .success(function(res) {
      $scope.running = res.running;
    });

  updateThreads();
  updateLocals();
});
