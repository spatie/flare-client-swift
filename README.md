# Send Swift errors and native crash reports to Flare

[![Latest Version](https://img.shields.io/github/v/release/spatie/flare-client-swift?style=flat-square)](https://github.com/spatie/flare-client-swift/releases)
[![Run tests](https://github.com/spatie/flare-client-swift/actions/workflows/tests.yml/badge.svg)](https://github.com/spatie/flare-client-swift/actions/workflows/tests.yml)

This repository contains the Swift client to send errors and native crash reports to [Flare](https://flareapp.io). The client can be installed using Swift Package Manager and works with Swift 6.0 and above.

The `Flare` product reports caught errors, context, breadcrumbs, and supplied stack traces. The optional `FlareCrashReporter` product captures native crashes with [PLCrashReporter](https://github.com/microsoft/plcrashreporter) and uploads them on the next launch. Upload failures are returned without throwing into your app's startup.

Supports macOS 12+, iOS 15+, and tvOS 15+. The reporting client also supports Linux. Native frames initially contain binary names and offsets; source-level symbolication requires matching release symbols and is not included.

## Documentation

You can find the documentation in [docs/README.md](docs/README.md), including [installation](docs/README.md#installation), [native crash capture](docs/README.md#native-crash-capture), and [Flare compatibility](docs/README.md#flare-compatibility).

## Changelog

Please see [CHANGELOG](CHANGELOG.md) for more information on what has changed recently.

## Testing

```shell
swift test
```

The [standalone example](Examples/FlareExample) can send a test report and exercise native crash recovery in its own process. See the [example instructions](docs/README.md#example-and-tests).

## Contributing

Please see [CONTRIBUTING](https://github.com/spatie/.github/blob/main/CONTRIBUTING.md) for details.

## Security

If you discover any security related issues, please email support@flareapp.io instead of using the issue tracker.

## License

The MIT License (MIT). Please see [License File](LICENSE.md) for more information.
