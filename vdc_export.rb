# coding: utf-8
#
# VEROVAL® duo control Blood pressure monitor data exporter
# Usage: ruby vdc_export.rb [ tty ] [ user ]
# Example: ruby vdc_export.rb /dev/ttyACM0 1

require 'rubyserial'
require 'bindata'
require 'date'
require 'csv'

module VDCDevice
  class Device
    STX = "\x02"
    ETX = "\x03"
    ENQ = "\x05"

    DATA_BYTES = 3000

    def initialize(device = '/dev/ttyACM0')
      @device = device
    end

    def count(user = 1)
      response = send_command VDCDevice::Command.get_observation_count(user)
      VDCDevice::Responses::ObservationCount.read response
    end

    def observations(user = 1)
      expected_observation_count = count(user).observation_count

      if expected_observation_count > 0
        raw_response = send_command VDCDevice::Command.get_observations(user)
        parsed_response = VDCDevice::Responses::Observations.read raw_response

        if expected_observation_count != parsed_response.observations.size
          raise "Expected #{expected_observation_count} observations but received #{parsed_response.observations.size}"
        end

        parsed_response
      else
        raise "No observations available for user ##{user}"
      end
    end

    private

    def send_command(command)
      response = ''

      serial_port.write(STX)
      serial_port.write(command)
      serial_port.write(ETX)
      sleep 1

      acknowledgement = VDCDevice::Responses::Acknowledgement.read read_response(1)
      serial_port.write(ENQ)
      sleep 0.5

      if acknowledgement.positive?
        response = read_response(DATA_BYTES)
      else
        if acknowledgement.negative?
          raise 'Negative acknowledgement received from the device'
        else
          raise 'Other non-positive acknowledgement received from the device'
        end
      end

      response
    ensure
      serial_port.close
    end

    def read_response(length)
      serial_port.read(length)
    end

    def serial_port
      if @serial_port.nil? || @serial_port.closed?
        @serial_port = Serial.new @device
      end

      @serial_port
    end
  end

  class Command
    GET_OBSERVATION_COUNT = "?MRN%d"
    GET_OBSERVATIONS = "?MDR%dA"

    def initialize(command)
      @command = command
    end

    def self.get_observation_count(user)
      validate_user user
      new GET_OBSERVATION_COUNT % user
    end

    def self.get_observations(user)
      validate_user user
      new GET_OBSERVATIONS % user
    end

    def self.validate_user(user)
      if user != 1 && user != 2
        raise ArgumentError, 'You must specify either 1 or 2 for the value of user'
      end
    end

    def to_s
      @command
    end

    private_class_method :validate_user
  end

  module Responses
    class Base < BinData::Record
      endian :little
    end

    class Acknowledgement < Base
      uint8 :flag

      def positive?
        flag == 6
      end

      def negative?
        flag == 21
      end

      def other?
        !positive? && !negative?
      end
    end

    class ObservationCount < Base
      skip length: 5
      string :raw_observation_count, read_length: 3, assert: lambda { (0..100).include? value.to_i }

      def observation_count
        raw_observation_count.to_i
      end

      def to_i
        observation_count
      end
    end

    class Observation < Base
      string :year, read_length: 2, assert: lambda { (0..99).include? value.to_i }
      string :month, read_length: 2, assert: lambda { (1..12).include? value.to_i }
      string :day, read_length: 2, assert: lambda { (1..31).include? value.to_i }
      string :hour, read_length: 2, assert: lambda { (0..23).include? value.to_i }
      string :minute, read_length: 2, assert: lambda { (0..59).include? value.to_i }
      string :regular_heart_beat, read_length: 1 #, assert: lambda { /[01]/ =~ value }
      string :systolic, read_length: 3, assert: lambda { (0..990).include? value.to_i }
      string :diastolic, read_length: 3, assert: lambda { (0..990).include? value.to_i }
      string :pulse, read_length: 3, assert: lambda { (0..990).include? value.to_i }
      string :body_movement, read_length: 1 #, assert: lambda { /[01]/ =~ value }
      string :incorrect_cuff_wrapping, read_length: 1 #, assert: lambda { /[01]/ =~ value }
      string :unsuitable_temperature, read_length: 1 #, assert: lambda { /[01]/ =~ value }
      skip length: 1
      string :usable, read_length: 1 #, assert: lambda { /[01]/ =~ value }

      def date
        Date.new year.to_i + 2000, month.to_i, day.to_i
      end

      def time
        DateTime.new year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i
      end
    end

    class Observations < Base
      skip length: 5

      array :observations, read_until: :eof, type: Observation
    end
  end
end

DEVICE = $ARGV[0] || '/dev/ttyACM0'
USER = ($ARGV[1] || 1).to_i

device = VDCDevice::Device.new(DEVICE)

csv = CSV.generate do |csv|

  csv << ['User', 'Date', 'Hour', 'Regular Heart Beat', 'Systolic', 'Diastolic', 'Pulse', 'Body Movement', 'Incorrect Cuff Wrapping', 'Unsuitable Temperature', 'Usable Measurement']

  device.observations(USER).observations.each do |o|
    csv << [USER, o.date, o.time.strftime('%H:%M'), o.regular_heart_beat, o.systolic.to_i, o.diastolic.to_i, o.pulse.to_i, o.body_movement, o.incorrect_cuff_wrapping, o.unsuitable_temperature, o.usable]
  end
end

puts csv
