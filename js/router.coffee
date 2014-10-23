app.config ['$routeProvider', ($routeProvider) ->
  $routeProvider.
    when '/main', {
      templateUrl: 'templates/main.html',
      controller: 'mainCtrl'
    }
    .otherwise {
      redirectTo: '/main'
    }
]
  