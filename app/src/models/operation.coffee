
class @Operation extends Model
  do @init

  @index 'uid'

  @pendingRawTransactionStream: () ->
    @_pendingRawTransactionStream ?= new Stream().open()
    @_pendingRawTransactionStream

  get: (key) ->
    switch key
      when 'total_value'
        if super('type') == 'sending'
          ledger.wallet.Value.from(super 'value').add(super 'fees')
        else
          super 'value'
      else super key