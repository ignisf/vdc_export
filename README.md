# vdc_export.rb

This tiny script exports blood pressure measurements as CSV from VEROVAL® duo
control devices.

## Installation

Just clone the repo and then execute:

    $ bundle

## Usage

    $ ruby vdc_export.rb [ TTY path ] [ User ]
    
For example:

    $ ruby vdc_export.rb /dev/ttyACM0 1
    
## License

Copyright &copy; Petko Bordjukov, 2019

The program is available as open source under the terms of the
[GNU Affero General Public License version 3](https://opensource.org/licenses/AGPL-3.0).
