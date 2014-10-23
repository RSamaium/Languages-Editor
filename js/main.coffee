fs_path = require 'path'
wrench = require 'wrench'
util = require 'util'
gui = require 'nw.gui'
msTranslator = require 'mstranslator'


appControllers = angular.module 'appControllers',  []

app = angular.module 'app', [
  'ngRoute',
  'ngResource',
  'appFilters',
  'appControllers'
]

app.config ['$routeProvider', ($routeProvider) ->
  $routeProvider.
    when '/main', {
      templateUrl: 'templates/main.html',
      controller: 'mainCtrl'
    }
    .when '/plurial', {
      templateUrl: 'templates/plurial.html',
      controller: 'plurialCtrl'
    }
    .when '/config', {
      templateUrl: 'templates/config.html',
      controller: 'configCtrl'
    }
    .otherwise {
      redirectTo: '/main'
    }
]


angular.module('appFilters', []).filter('translateFilter', ->
    (item, type) -> 
      obj = {}
      angular.forEach item, (value, key) ->
        bool = false

        switch type
          when "no_translate" then bool = true if value.text is  ""
          when "translate" then bool = true if value.text != ""
          else
            bool = true

        obj[key] = value if bool

      obj   

).filter('translateSearch', ->
    (item, params) -> 
      text = params.search
      obj = {}
      if not text
        return item
      
      text = text.replace(/[\(\)\|\[\]\+\?\*\\]/, "")
      reg = new RegExp(text, "g")

      angular.forEach item, (value, key) ->
        bool = false
        switch params.type
          when "id" then bool = true if reg.test(key)
          when "from" then bool = true if reg.test(value.init)
          when "to" then bool = true if reg.test(value.text)
          else
            bool = reg.test(value.text) or reg.test(value.init)

        obj[key] = value if bool

      obj   
)



app.factory 'file', ($rootScope) ->

    CONFIG_NAME = "config.lang"    

    service = {}

    service.langs = {}

    service.config = {}

    service.extension = {
      ".php": /\Wt\(("|')([a-zA-Z0-9_-]+)("|')/g
      ".js": /("|')([a-zA-Z0-9_-]+)("|')\.t\(/g
    }

    service.modified = {}

    service.isModified = ->
      for id, bool of @modified
        return true if bool
      false

    service.onModified = (id) ->
      if not @modified[id]?
        @modified[id] = 0
      @modified[id]++
      @refreshInfo()

    service.extract = (json) ->
        @data = json[0]
        @head = json[1]

    service.setPath = (path) ->
    	  @path = path

    service.getKeyLang = (lang) ->
        @langs[lang][0]


    service.analysis = (path, progress, onfinish) ->
      files = wrench.readdirSyncRecursive path

      i=0

      finish = =>
         onfinish() if onfinish
         @refreshCurrent()

      read = =>
        file = files[i]
        ext = fs_path.extname file
        if @extension[ext]
          data = fs.readFileSync "#{path}/#{file}", 'utf8'
          match = data.match @extension[ext]
          if match
              for m in match
                find = null
                find = @extension[ext].exec m
                id = find[2]
                @extension[ext].lastIndex = 0
                if not @idExist @init, id
                  @add id, ""
        i++
        if files.length == i
          finish()
        else
          percent = (i * 100) //  files.length
          progress percent, "#{path}/#{file}" if progress
          setTimeout(read, 1)


      read()
           

    service.add = (id, val) ->
        for key, value of @langs
          @langs[key][0][id] = if key == @text then val else ""
          @onModified key

    service.remove = (id) ->
        for key, value of @langs
          delete @langs[key][0][id]
          @onModified key

    service.change = (id, val) ->
        @langs[@text][0][id] = val
        @onModified @text
        @refreshCurrent()

    service.new = (id, name) ->
        obj = {}
        if @langs[@init]
          for _id, val of @langs[@init][0]
            obj[_id] = ""

        @langs[id] = [
           obj,
           {
             name: name
           }
        ]
        @text = id
        @save()
        @refresh()

    service.save = (path, id = @text) ->
        path = if path  then path else "#{@path}/#{id}"
        fs.writeFileSync path,  JSON.stringify @langs[id], {
          encoding: "utf8"
        }
        @modified[id] = 0
        @refreshInfo()

    service.saveConfig = () ->
        path = "#{@path}/#{CONFIG_NAME}"
        @config.date_modified = new Date().getTime()
        fs.writeFileSync path,  JSON.stringify @config, {
          encoding: "utf8"
        }

    service.openConfig = () ->
        path = "#{@path}/#{CONFIG_NAME}"
        if fs.existsSync path
          f = fs.readFileSync path, 'utf8'
          @setConfig angular.fromJson f

    service.getConfig = ->
        @config


    service.setConfig = (config) ->
        @config = config

    service.allSave = (path) ->
        for id, val of @langs
          if @modified[id] > 0
            @save(path, id)
        @saveConfig()

    # ("en.json", "fr.json")
    service.getCurrentLang = (init = @init, _text = @text) ->
        text = {}

        if init is "id"
          init = @init
          
        lang_init = @getKeyLang init
        lang_text = @getKeyLang _text

        for id, value of  @langs[init][0]
          cond = @display_id or !lang_init[id]
          text[id] = {
            init: if cond then id else lang_init[id]
            text: lang_text[id]
            display_id: cond
            id: id
          }
          
        @text = _text
        @init = init

        text

    service.open = (path) ->
      @setPath path
      @refresh()

    service.getName = (id) ->
      @langs[id][1].name


    service.getPlurials = (id = @text) ->
      @langs[id][1].plurial

    service.setPlurials = (key, val, id = @text) ->
      @langs[id][1].plurial[key] = val
      @onModified id


    service.removePlurial = (key, id = @text) ->
      delete @langs[id][1].plurial[key]
      @onModified id


    service.idExist = (lang, id) ->
       return true if @langs[lang][0][id]
       false

    service.getLangs = ->
      langs = []
      for id, val of @langs
        langs.push {name: val[1].name, id: id}
      langs

    service.existFile = ->
      @number != 0


    service.initLangs = ->
      dir = @path #  fs_path.dirname
      files = fs.readdirSync @path
      @number = 0
      ret = []
      for file in files

        ext = fs_path.extname file
       
        if ext != ".json"
          continue

        f = fs.readFileSync "#{dir}/#{file}", 'utf8'

        try
          json = (angular.fromJson f)
        catch
          alert "Impossible d'ouvrir #{dir}/#{file}. Le fichier est corrompu."
          continue;
        

        @langs[file] = json
        if not @langs[file][1].plurial
          @langs[file][1].plurial = {}
        @init = file
        @text = file
        @number++;
        ret.push {name: json[1].name, id: file} if json[1].name

      @openConfig()

      $rootScope.$broadcast 'onloadLangs'

      if @number is 0
        $('#newFile').modal()
        false
      else
        ret

    service.getSelected = (list, val) ->
      for l in list
        if (l.id == val)
          return l


    service.refresh = ->
      $rootScope.$broadcast 'refreshTable'
      

    service.refreshCurrent = ->
      $rootScope.$broadcast 'refreshCurrentTable'
    

    service.refreshInfo = ->
      $rootScope.$broadcast 'refreshInfo'
      

    service.bing = {
      init: (callback) -> 
        if not @client
          @client = new msTranslator {
            client_id: service.config.bing.client_id
            client_secret: service.config.bing.client_secret
          }
          @client.initialize_token((keys) ->
              callback keys
          )
        else
          callback()

      translate: (text, callback) ->
        @client.translate { 
              text: text
              from: service.init.split(".")[0]
              to: service.text.split(".")[0]
            }, ((err, data) ->
            callback data
        )
    }

    service



appControllers.controller 'mainCtrl', ['$scope', 'file', ($scope, $file) -> 

    editor = new Pen('#markdown-editor')
    key_markdown = ""

    $scope.select_lang = (val) ->
        localStorage["init"] = val.id
        $file.display_id = if val.id is "id" then true else false
        $scope.langs = $file.getCurrentLang val.id

    $scope.select_lang_to_translate = (val) ->
        localStorage["to"] = val.id
        $scope.langs = $file.getCurrentLang null, val.id

    $scope.is_modified = false

  
    $scope.$on 'refreshInfo', (event, args) ->
        str = ""
        for id, nb of $file.modified
          str += "#{$file.getName id}, "
        str = str.replace /, $/, ""
        $scope.info_modified = "Les langues #{str} ont été modifiés."
        $scope.link_save = "Pensez à enregistrer votre travail"
        $scope.is_modified = $file.isModified()

    $scope.linkSave = ->
      $file.allSave()

    $scope.$on 'refreshCurrentTable', (event, args) ->
       $scope.langs = $file.getCurrentLang()
  	
    $scope.$on 'refreshTable', (event, args) ->
        langs = $file.initLangs()

        if (langs is false)
          return
        
        $scope.langs = $file.getCurrentLang()

        $scope.all_langs = [{name: "ID", id: "id"}].concat langs
        $scope.all_langs_real = langs

        $scope.choice_lang =  $file.getSelected $scope.all_langs, $file.init
        $scope.choice_lang_to_translate = $file.getSelected $scope.all_langs_real, $file.text

        $scope.showPanel = $file.existFile()


    $scope.changeText = (id, val) ->
        $file.change id, val

    $scope.edit = () ->

    $scope.translate = (key, text) ->
      $file.bing.init(-> 
         $file.bing.translate(text, (data) ->
            $file.change key, data
         )
      )
      

    $scope.removeText = (id) ->
        $file.remove id
        $scope.langs = $file.getCurrentLang()

    $scope.addText = (ev, id, val) ->
        if ev.keyCode == 13
          if id and val
             $file.add id, val
             $scope.langs = $file.getCurrentLang()
          else
            alert "Veuillez rentrer un identifiant et une valeur"

    $scope.searchType = "*"

    $scope._searchType = (type) ->
      $scope.searchType = type

    $scope.openMarkdown = (key, val) ->
        key_markdown = key
        $("#markdown-editor").text val
        editor.rebuild()
        $("#markdown").modal()

    $scope.validMarkdown = () ->
        $("#markdown").modal 'hide'
        text = $("#markdown-editor").html()
        text = text.replace(/<div>/g, "\\n")
        $file.change key_markdown, html2markdown text


    if localStorage["path"]
        $file.open localStorage["path"]
    else
        $("#openGroupLang").modal()

    Mousetrap.bind ['ctrl+s'], ->
      $file.allSave()
      false
    
    
] 

appControllers.controller 'menuCtrl', ['$scope', 'file', ($scope, $file) -> 
  win = gui.Window.get()

  $scope.file = "Fichier"

  $scope.openDirectory = -> 
  	chooser = $ '#dirDialog'
  	chooser.change((evt) ->
      path =  $(this).val()
      #file = fs.readFileSync path, 'utf8'
      #json = angular.fromJson file
      
      #$file.extract json
      localStorage["path"] = path
      $file.open path
  	)
  	chooser.trigger 'click'
  	false

  $scope.save = -> 
     $file.allSave()
     false

  $scope.newFile = -> 
     $('#newFile').modal()
     false

  $scope.analysisProject = ->
      $('#analysisFile').modal()
      false

  Mousetrap.bind ['ctrl+o'], ->
      $scope.openDirectory()
      false

  Mousetrap.bind ['ctrl+n'], ->
      $scope.newFile()
      false

  win.on "close", ->
    if $file.isModified()
      if confirm "Voulez vous enregistrer les modifications et quitter ?"
        $file.allSave()
      @close true
    else
      @close true

]

appControllers.controller 'analysisCtrl', ['$scope', 'file', ($scope, $file) -> 
  

  chooser = $ '#analysisDialog'

  if localStorage["analysis_path"]
    chooser.attr "nwworkingdir", localStorage["analysis_path"]
    $scope.pathProject = localStorage["analysis_path"]

  $scope.choiceProject = ->
   
    chooser.change((evt) ->
      path =  $(this).val()
      localStorage["analysis_path"] = path
      $scope.pathProject = path
     # chooser.attr "nwworkingdir", path

      $scope.$apply()
    )

    chooser.trigger 'click'

  $scope.scripts = $file.extension

  $scope.getLogo = (ext) ->
     /\.(.+)$/.exec(ext)[1]

  $scope.removeExt = (ext) ->
     delete $file.extension[ext]

  $scope.addExt = (ext, regex) ->
    if not /^\./.test ext
      ext = ".#{ext}"
    $file.extension[ext] = regex

  $scope.changeExt = (ext, regex) ->
       delete $file.extension[ext]
       $file.extension[ext] = regex

  $scope.clickAnalysis = ->
    $('#analysisFile').modal "hide"
    $('#percentAnalysis').modal()
    $file.analysis $scope.pathProject, (percent, path) ->
      $scope.percent = percent
      $scope.path_found = path
      $scope.$apply()
    , ->
      $('#percentAnalysis').modal "hide"
    

]

appControllers.controller 'directoryCtrl', ['$scope', 'file', ($scope, $file) -> 
  
  chooser = $ '#dirDialog'

  if localStorage["path"]
    $scope.dirPath = localStorage["path"]

  $scope.dirDialog = ->
   
    chooser.change((evt) ->
      path =  $(this).val()
      localStorage["path"] = path
      $scope.dirPath = path
     # chooser.attr "nwworkingdir", path

      $scope.$apply()
    )

    chooser.trigger 'click'


  $scope.choiceDirectory = ->
     $file.open $scope.dirPath
     $('#openGroupLang').modal('hide')

]

appControllers.controller 'newFileCtrl', ['$scope', 'file', ($scope, $file) -> 
  
  $scope.$on 'onloadLangs', (event, args) ->
    $scope.is_empty = !$file.existFile()

  icons = fs.readdirSync "img/icons"
  langs = []

  for lang in icons
    m = lang.match /^(.+)\.png$/
    if m
      langs.push m[1]

  $scope.btn_select_lang = "Sélectionnez une langue"

  $scope.langs = langs
  $scope.selectLang = (id) ->
    $scope.btn_select_lang = id
    $scope.langName = id

  $scope.getLangName = (id) ->
    id


  $scope.createLang = ->
    $file.new "#{$scope.btn_select_lang}.json", $scope.langName
    $('#newFile').modal('hide')
]

appControllers.controller 'plurialCtrl', ['$scope', 'file', ($scope, $file) -> 

  lang_id = $file.text

  $scope.add_key = ""

  $scope.langs = $file.getLangs()

  $scope.select_lang = (val) ->
    $scope.plurials = $file.getPlurials val.id

  $scope.choice_lang = $file.getSelected $scope.langs, lang_id
  $scope.select_lang {id: lang_id}

  $scope.removePlurial = (key) ->
    $file.removePlurial key, lang_id

  $scope.addPlurial = ->
    $file.setPlurials "p#{$scope.add_key}", [$scope.add_plurial, $scope.add_singular, $scope.add_dual], lang_id

  $scope.savePlurial = ->
    $file.allSave()

  $scope.changePlurial = (key, val) ->
    $file.setPlurials key, val, lang_id
    
]

appControllers.controller 'configCtrl', ['$scope', 'file', ($scope, $file) -> 

   $scope.config = $file.getConfig()
   $scope.langs = ""

   $scope.path = $file.path
   langs = $file.getLangs()

   for lang in langs
      $scope.langs += "#{lang.name}, "

   $scope.langs = $scope.langs.replace(/, $/, "")

   $scope.saveConfig = ->
      $file.config = $scope.config
      $file.allSave()
    
]
