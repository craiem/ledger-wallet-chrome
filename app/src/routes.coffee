# routes that do not need a plugged ledger wallet
ledger.router ?= {}
ledger.router.ignorePluggedWalletForRouting = yes
ledger.router.pluggedWalletRoutesExceptions = [
  '/',
  '/onboarding/device/plug'
]

# routes declarations
@declareRoutes = (route, app) ->
  ## Default
  route '/', ->
    app.router.go '/onboarding/device/plug', {animateIntro: yes}

  ## Onboarding
  # Device
  route '/onboarding/device/plug', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingDevicePlugViewController

  route '/onboarding/device/unplug', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingDeviceUnplugViewController

  route '/onboarding/device/pin', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingDevicePinViewController

  route '/onboarding/device/opening', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingDeviceOpeningViewController

  route '/onboarding/device/error', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingDeviceErrorViewController

  route '/onboarding/device/wrongpin', (params) ->
    app.router.go '/onboarding/device/error',
      error: t 'onboarding.device.errors.wrongpin.wrong_pin'
      message: _.str.sprintf t('onboarding.device.errors.wrongpin.tries_left'), params['?params'].tries_left
      indication: t 'onboarding.device.errors.wrongpin.unplug_plug'

  route '/onboarding/device/frozen', (params) ->
    app.router.go '/onboarding/device/error',
      error: t 'onboarding.device.errors.frozen.wallet_is_frozen'
      message: t 'onboarding.device.errors.frozen.blank_next_time'
      indication: t 'onboarding.device.errors.frozen.unplug_plug'

  route '/onboarding/device/unsupported', (params) ->
    app.router.go '/onboarding/device/error',
      error: t 'onboarding.device.errors.unsupported.device_unsupported'
      message: t 'onboarding.device.errors.unsupported.unsuported_kind'
      indication: t 'onboarding.device.errors.unsupported.get_help'

  # Management
  route '/onboarding/management/security', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementSecurityViewController

  route '/onboarding/management/done', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementDoneViewController

  route '/onboarding/management/welcome', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementWelcomeViewController

  route '/onboarding/management/pinconfirmation', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementPinconfirmationViewController

  route '/onboarding/management/pin', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementPinViewController

  route '/onboarding/management/seed', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementSeedViewController

  route '/onboarding/management/summary', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementSummaryViewController

  route '/onboarding/management/provisioning', (params) ->
    app.navigate ONBOARDING_LAYOUT, OnboardingManagementProvisioningViewController

  ## Wallet
  # Accounts
  route '/wallet/accounts/{id}/show', (params) ->
    app.navigate WALLET_LAYOUT, WalletAccountsShowViewController

  # Send
  route '/wallet/send/index', (params) ->
    dialog = new WalletSendIndexDialogViewController()
    dialog.show()

  # Receive
  route '/wallet/receive/index', (params) ->
    dialog = new WalletReceiveIndexDialogViewController()
    dialog.show()

  # Help
  route '/wallet/help/index', (params) ->
    window.open t 'application.support_url'

  # Operations
  route '/wallet/accounts/{id}/operations', (params) ->
    app.navigate WALLET_LAYOUT, WalletOperationsIndexViewController
