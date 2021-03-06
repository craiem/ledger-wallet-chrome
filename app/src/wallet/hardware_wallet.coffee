
@ledger.wallet ?= {}

@ledger.wallet.States =
  UNDEFINED: undefined
  LOCKED: 'locked'
  UNLOCKED: 'unlocked'
  FROZEN: 'frozen'
  BLANK: 'blank'
  UNPLUGGED: 'unplugged'
  DISCONNECTED: 'disconnected'

@ledger.wallet.Firmware =
  V1_4_11: 0x0001040b0146
  V1_4_12: 0x0001040c0146
  V1_4_13: 0x0001040d0146

@ledger.wallet.Attestation =
  String: "04c370d4013107a98dfef01d6db5bb3419deb9299535f0be47f05939a78b314a3c29b51fcaa9b3d46fa382c995456af50cd57fb017c0ce05e4a31864a79b8fbfd6"
  Bytes: []

for i in [0...(ledger.wallet.Attestation.String.length / 2)]
  ledger.wallet.Attestation.Bytes.push parseInt(ledger.wallet.Attestation.String.substring(i, i + 2), 16)

class @ledger.wallet.HardwareWallet extends EventEmitter

  _state: ledger.wallet.States.UNDEFINED

  constructor: (@manager, @id, @lwCard) ->
    @_xpubs = {}
    @_vents = new EventEmitter()
    do @_listenStateChanges

  connect: () ->
    @_vents.once 'LW.CardConnected', (event, data) =>
      @_vents.once 'LW.FirmwareVersionRecovered', (event, data) =>
        data.lW.getOperationMode()
        data.lW.plugged()
        @emit 'connected', @
      data.lW.recoverFirmwareVersion()
    @_lwCard = new LW(0, new BTChip(@lwCard), @_vents)

  disconnect: () ->
    @_setState(ledger.wallet.States.DISCONNECTED)
    @emit 'disconnected'
    @manager.addRestorableState({label: 'frozen'}, 45000) if @_frozen?
    if @_numberOfRetry?
      @manager.removeRestorableState(state) for state in @manager.findRestorableStates({label: 'numberOfRetry'})
      @manager.addRestorableState({label: 'numberOfRetry', numberOfRetry: @_numberOfRetry}, 45000)

  getFirmwareVersion: () -> @_lwCard.getFirmwareVersion()

  getIntFirmwareVersion: () -> parseInt(@_lwCard.firmwareVersion.toString(), 16)

  getState: (callback) ->
    if @_state is ledger.wallet.States.UNDEFINED
      @once 'state:changed', (e, state) => callback?(state)
    else
      callback?(@_state)

  unlockWithPinCode: (pin, callback) ->
    throw 'Cannot unlock a device if its current state is not equal to "ledger.wallet.States.LOCKED"' if @_state isnt ledger.wallet.States.LOCKED
    unbind = @_performLwOperation
      onSuccess:
        events: ['LW.PINVerified']
        do:  =>
          @_lwCard.dongle.card.sendApdu_async(0xE0, 0x26, 0x01, 0x01, new ByteString(Convert.toHexByte(0x01), HEX), [0x9000]).then =>
            ## This needs a BIG refactoring
            l @getFirmwareVersion()
            if @getIntFirmwareVersion() >= ledger.wallet.Firmware.V1_4_13
              l 'GOT 13'
              # ledger.app.wallet._lwCard.dongle.card.sendApdu_async(0xE0, 0x26, 0x01, 0x01, new ByteString(Convert.toHexByte(0x01), HEX), [0x9000]).then(function (){l('done');}).fail(e)
              #.sendApdu_async(0xe0, 0x26, 0x00, 0x00, new ByteString(Convert.toHexByte(operationMode), HEX), [0x9000])
              @_lwCard.dongle.card.sendApdu_async(0xE0, 0x26, 0x01, 0x00, new ByteString(Convert.toHexByte(0x01), HEX), [0x9000])
              .then =>
                  l 'DONE'
              .fail => l 'FAIL', arguments
            @_setState(ledger.wallet.States.UNLOCKED)
            do unbind
            callback?(yes)
          .fail =>
              do unbind
              callback? no, title: 'Not supported dongle', code: ledger.errors.NotSupportedDongle
      onFailure:
        events: ['LW.ErrorOccured']
        do: (error) =>
          if error.title is 'wrongPIN'
            retryNumber = parseInt(error.message.substr(-1))
            @_numberOfRetry = retryNumber
            do unbind
            callback?(no, {title: 'Wrong PIN', code: ledger.errors.WrongPinCode, error, retryCount: retryNumber})
    @_lwCard.verifyPIN pin

  setup: (pincode, seed, callback) ->
    throw 'Cannot setup if the wallet is not blank' if @_state isnt ledger.wallet.States.BLANK and @_state isnt ledger.wallet.States.FROZEN
    onSuccess = () =>
      @once 'connected', =>
      callback?(yes)

    onFailure = (ev, error) =>
      e error.title
      e error.errors
      if error.title is 'performSetupInvalidData'
        do unbind
      if error.title is 'errorOccuredInSetup'
        callback?(no)
      do unbind

    unbind = () =>
      @_vents.off 'LW.SetupCardInProgress', onSuccess
      @_vents.off 'LW.ErrorOccured', onFailure
    @_vents.on 'LW.SetupCardInProgress', onSuccess
    @_vents.on 'LW.ErrorOccured', onFailure
    @_lwCard.performSetup(pincode, seed, 'qwerty')

  getBitIdAddress: (callback) ->
    throw 'Cannot get bit id address if the wallet is not unlocked' if @_state isnt ledger.wallet.States.UNLOCKED

    onSuccess = (e, data) =>
      _.defer =>
        @_bitIdData = data.result
        callback?(@_bitIdData.bitcoinAddress.value)
        do unbind

    onFailure = (ev, error) =>
      _.defer =>
        callback?(null, error)
        do unbind

    unbind = =>
      @_vents.off 'LW.getBitIDAddress', onSuccess
      @_vents.off 'LW.ErrorOccured', onFailure
    if @_bitIdData?
      callback?(@_bitIdData.bitcoinAddress.value)
    else
      @_vents.on 'LW.getBitIDAddress', onSuccess
      @_vents.on 'LW.ErrorOccured', onFailure
      @_lwCard.getBitIDAddress()

  signMessageWithBitId: (message, callback) ->
    throw 'Cannot get bit id address if the wallet is not unlocked' if @_state isnt ledger.wallet.States.UNLOCKED

    onSuccess = (e, data) =>
      _.defer =>
        callback?(data, null)
        do unbind

    onFailure = (ev, error) =>
      _.defer =>
        callback?(null, error)
        do unbind

    unbind = =>
      @_vents.off 'LW.getMessageSignature', onSuccess
      @_vents.off 'LW.getMessageSignature:error', onFailure
    @_vents.on 'LW.getMessageSignature', onSuccess
    @_vents.on 'LW.getMessageSignature:error', onFailure
    @_lwCard.getMessageSignature(message)

  getPublicAddress: (derivationPath, callback) ->
    throw 'Cannot get a public while the key is not unlocked' if @_state isnt ledger.wallet.States.UNLOCKED
    try
      @_lwCard.dongle.getWalletPublicKey_async(derivationPath)
      .then (result) =>
          ledger.wallet.HDWallet.instance?.cache?.set [[derivationPath, result.bitcoinAddress.value]]
          _.defer ->
            callback?(result)
          return
      .fail (error) =>
          e error
          _.defer ->
            callback?(null, error)
          return
    catch error
      @_updateStateFromError(error)
      callback?(null, error)

  getExtendedPublicKey: (derivationPath, callback) ->
    throw 'Cannot get a public while the key is not unlocked' if @_state isnt ledger.wallet.States.UNLOCKED
    return callback(@_xpubs[derivationPath]) if @_xpubs[derivationPath]?
    xpub = new ledger.wallet.ExtendedPublicKey(@, derivationPath)
    xpub.initialize () =>
      @_xpubs[derivationPath] = xpub
      callback xpub

  getExtendedPublicKeys: () -> @_xpubs

  isDongleCertified: (callback) ->
    randomValues = new Uint32Array(2)
    crypto.getRandomValues(randomValues)
    random = _.str.lpad(randomValues[0].toString(16), 8, '0') + _.str.lpad(randomValues[1].toString(16), 8, '0')
    adpu = 'E0C2000008' + random
    p = @sendAdpu new ByteString(adpu, HEX), [0x9000]
    p.then (result) =>
      attestation = result.toString(HEX)
      @attestation =
        raw: attestation
        keyBatchId: attestation.substring(0, 8)
        keyDerivationId: attestation.substring(8, 16)
        supportedOperationBitFlag: attestation.substring(16, 18)
        firmwareMajor: attestation.substring(18, 22)
        firmwareMinor: attestation.substring(22, 24)
        firmarePatch: attestation.substring(24, 26)
        loaderIdMajor: attestation.substring(26, 28)
        loaderIdMinor: attestation.substring(28, 30)
        signature: attestation.substring(30)
      l @attestation, random
      try
        SHA256  = new  JSUCrypt.hash.SHA256()
        domain =  JSUCrypt.ECFp.getEcDomainByName("secp256k1")
        pubKey = new JSUCrypt.key.EcFpPublicKey(256, domain)
        pubKey.W =
          getUncompressedForm: -> ledger.wallet.Attestation.Bytes
        ecsig = new JSUCrypt.signature.ECDSA(SHA256)
        ecsig.init(pubKey,  JSUCrypt.signature.MODE_VERIFY)
        sigBytes = (parseInt(@attestation.signature.substring(i, i + 2), 16) for i in [0...(@attestation.signature.length / 2)])
        ver = ecsig.verify(random, sigBytes)
        l sigBytes
        l 'Verif', ver
        return
      catch er
        e er
    p.fail (result) =>
      e result

  sendAdpu: (cla, ins, p1, p2, opt1, opt2, opt3, wrapScript) -> @_lwCard.dongle.card.sendApdu_async(cla, ins, p1, p2, opt1, opt2, opt3, wrapScript)

  _setState: (newState) ->
    @_state = newState
    switch newState
      when ledger.wallet.States.LOCKED then @emit 'state:locked', @_state
      when ledger.wallet.States.UNLOCKED then @emit 'state:unlocked', @_state
      when ledger.wallet.States.FROZEN then @emit 'state:frozen', @_state
      when ledger.wallet.States.BLANK then @emit 'state:blank', @_state
      when ledger.wallet.States.UNPLUGGED then @emit 'state:unplugged', @_state
      when ledger.wallet.States.DISCONNECTED then @emit 'state:disconnected', @_state
    @emit 'state:changed', @_state

  _listenStateChanges: () ->
    @_vents.on 'LW.PINRequired', (e, data) =>
      restoreStates = @manager.findRestorableStates({label: 'numberOfRetry'})
      if restoreStates.length > 0
        @_numberOfRetry = restoreStates[0].numberOfRetry
      @_setState ledger.wallet.States.LOCKED
    @_vents.on 'LW.SetupCardLaunched', (e, data) =>
      if @manager.findRestorableStates({label: 'frozen'}).length == 0
        @_setState ledger.wallet.States.BLANK
      else
        @_setState ledger.wallet.States.FROZEN
    @_vents.on 'LW.unplugged', () =>
      @_setState ledger.wallet.States.UNPLUGGED
    @_vents.on 'LW.ErrorOccured', (e, data) =>
      switch
        when (data.title is 'dongleLocked' or (data.title is 'wrongPIN' and data.message.indexOf('63c0') != -1))
          @_frozen = yes
          @_setState ledger.wallet.States.FROZEN

  _updateStateFromError: (error) ->
    errors = (/(6982)|(6faa)|(6985)/g).exec(error)
    return unless errors
    switch
      when errors[1]? then @_setState(ledger.wallet.States.LOCKED)
      when errors[2]? then @_setState(ledger.wallet.States.FROZEN)
      when errors[3]? then @_setState(ledger.wallet.States.BLANK)

  _performLwOperation: (operation) ->
    unbind = () =>
      for callbackName, params of operation
        for event in params.events
          @_vents.off event, params.do

    for callbackName, params of operation
      for event in params.events
       do (params) =>
          @_vents.on event, (ev, data) ->
            _.defer () ->
              params.do(data, ev)
    unbind