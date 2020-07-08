# frozen_string_literal: true

module Jobs
  module Cron
    class Archive
      def self.process
        # ORDER_MAX_AGE in days
        order_max_age = ENV.fetch('ORDER_MAX_AGE', 28)

        # Cancel orders that older than max_order_age
        Order.where('created_at > ? AND state = ?', Time.now - order_max_age.days, 100).each do |o|
          Order.cancel(o.id)
        end

        yaml = ::Pathname.new("config/database.yml")
        return {} unless yaml.exist?

        config = ::SafeYAML.load(::ERB.new(yaml.read).result)['archive_production']

        return if config.blank?

        # Connection to the archive database
        archive_database = Mysql2::Client.new(config)

        # Execute sp.sql
      end
    end
  end
end
