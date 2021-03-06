String.prototype.startsWith = (s) -> this.lastIndexOf(s, 0) == 0

window.FlashCard = Backbone.Model.extend
  defaults  :
    kana    : ''
    romaji     : []
    charset    : 'kana'
    guessState : ''
  initialize : () ->
    _.bindAll this, 'random'
  isWrong    : (guess) ->
    minLength = (_.max this.get('romaji'), (s) -> s.length || 0).length
    guess.length >= minLength and not _.any this.get('romaji'), (s) -> s.startsWith(guess.toLowerCase())
  isCorrect  : (guess) ->  _.contains(this.get('romaji'), guess.toLowerCase())
  random     : (callback) ->
    self = this
    $.ajax
      url : "#{ this.get('charset') }/random/"
      data : { prevKana : this.get('kana') }
      success : (flashCard) ->
        flashCard.guessState = ''
        self.set flashCard
        callback() if callback?


window.KanaFilter = Backbone.Model.extend
  defaults :
    hiragana : false
    katakana : false
  validate : (attrs) ->
    desiredModel = _.extend(this.toJSON(), attrs)
    if not desiredModel.hiragana and not desiredModel.katakana
      return "Must select at least one character set"
  select   : (charset) ->
    switch charset
      when 'hiragana' then return this.save { hiragana : true, katakana : false }
      when 'katakana' then return this.save { hiragana : false, katakana : true }
      when 'both' then return this.save { hiragana : true, katakana : true }
      else return false
  url      : () ->
    return '/kanafilter/'
  kanaUrl : () ->
    if this.get("hiragana") and this.get("katakana")
      return 'kana'
    else if this.get("hiragana")
      return 'hiragana'
    else if this.get("katakana")
      return 'katakana'
    else
      throw Error("invalid KanaFilter model state")

signalGuess = (flashCard, guess, guessResult) ->
  $.ajax
    url  : "/guess/"
    type : "POST"
    data :
      guess       : guess?.toLowerCase()
      guessResult : guessResult
      kana        : flashCard.get('kana')
      charset     : flashCard.get('charset')

$(document).ready () ->
  window.KanaFilterView = Backbone.View.extend
    template : _.template $('#kanafilter-template').html()
    events     :
      "click .select-button.unselected" : "select"
    initialize : () ->
      _.bindAll this, 'render'
      this.model.bind 'change', this.render
    render     : () ->
      $(this.el).html this.template(this.model.toJSON())
      return this
    select     : (e) ->
      this.model.select $(e.target).data('charset')
      return this

  window.FlashCardView = Backbone.View.extend
    events :
      "keyup input[type=text]" : "guess"
    initialize : () ->
      _.bindAll this, 'render', 'guess'
      this.model.bind 'change', this.render
    guess : (e) ->
      guess = $(e.target).val()
      if this.model.isCorrect(guess)
        this.$('.textframe').addClass('correct')
        this.$('.textframe').removeClass('wrong')
        this.$('input[type=text]').val('')
        signalGuess this.model, guess, 'correct'
        this.model.set { guessState : 'correct' }
        self = this
        this.model.random () ->
          clearTimeout self.timerID
          self.$('input[type=text]').focus()
          self.timerID = setTimeout ()->
            self.$('.textframe').removeClass('correct')
          , 888
      else if this.model.isWrong(guess)
        if this.model.get('guessState') == ''
          signalGuess this.model, guess, 'wrong'
          this.model.set { guessState : 'wrong' }
        this.$('.textframe').addClass('wrong')
      else
        this.model.set { guessState : '' }
        this.$('.textframe').removeClass('wrong')
    render : () ->
      this.$('p.kana').text this.model.get('kana')
      return this

$(document).ready () ->
  window.kanaFilter = new KanaFilter
  window.flashCard = new FlashCard

  window.kanaFilterView = new KanaFilterView
    el       : '#kana-filter'
    model    : window.kanaFilter

  window.flashCardView = new FlashCardView
    el       : '#flashcard'
    model    : window.flashCard

  kanaFilter.bind 'change', (model) ->
    flashCard.set { charset : model.kanaUrl() }
    flashCard.random () ->
      flashCardView.$('input[type=text]').focus()

  kanaFilter.fetch
    success : () ->
      kanaFilterView.render()
      flashCardView.render()

$('#flashcard input[type=text]').live 'focus', () ->
  if $(this).hasClass('prompt')
    $(this).removeClass('prompt')
    $(this).val('')

$('#flashcard input[type=text]').live 'blur', () ->
  if $.trim($(this).val()) == ''
    $(this).addClass('prompt')
    $(this).val('Enter Romaji...')

skipBtnTimerRunning = false
$('#flashcard .skip-button').live 'click', () ->
  if not skipBtnTimerRunning
    signalGuess flashCard, undefined, 'skip'
    skipBtnTimerRunning = true
    $('#flashcard p.response').text(window.flashCard.get('romaji').join(', '))
    clearTimeout skipBtnTimerID
    skipBtnTimerID = setTimeout ()->
      #TODO make it fade instead
      $('#flashcard p.response').text('')
      $('#flashcard input[type=text]').val('')
      window.flashCard.random () ->
        flashCardView.$("input[type=text]").focus()
      skipBtnTimerRunning = false
    , 1000

