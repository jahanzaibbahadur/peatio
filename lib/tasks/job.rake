# frozen_string_literal: true

namespace :job do
  namespace :order do
    desc 'Close orders older than ORDER_MAX_AGE.'
    task close: :environment do
      order_max_age = ENV.fetch('ORDER_MAX_AGE', 40_320)

      # Cancel orders that older than max_order_age
      Order.where('created_at < ? AND state = ?', Time.now - order_max_age, 100).each do |o|
        Order.cancel(o.id)
      end
    end

    desc 'Archive and delete old cancelled orders without trades to the archive database.'
    task archive: :environment do
      time = Time.now.to_s(:db)
      result = ActiveRecord::Base.connection.exec_query("SELECT * FROM `orders` WHERE updated_at < DATE_SUB('#{time}', INTERVAL 1 WEEK) AND state = -100 AND trades_count = 0;")
      # Connection to the archive database
      ActiveRecord::Base.establish_connection(:archive_db)
      # Copy old cancelled orders without trades to the archive database
      ActiveRecord::Base.connection.transaction do
        result.each_slice(1000) do |batch|
          queries = []
          batch.each do |order|
            queries << order_values(order)
          end
          ActiveRecord::Base.connection.exec_query(order_insert + queries.join(', ') + ';')
        end
      end

      # Connection to the main database
      ActiveRecord::Base.establish_connection(ENV['RAILS_ENV'].to_sym)

      # Delete old cancelled orders without trades
      ActiveRecord::Base.connection.exec_query("DELETE FROM `orders` WHERE updated_at < DATE_SUB('#{time}', INTERVAL 1 WEEK) AND state = -100 AND trades_count = 0;")
    end

    def order_insert
      'INSERT INTO orders (id, uuid, remote_id, bid, ask, market_id, price, ' \
      'volume, origin_volume, maker_fee, taker_fee, state, type, member_id, ord_type, ' \
      'locked, origin_locked, funds_received, trades_count, created_at, updated_at) VALUES ' \
    end

    def order_values(order)
      order['remote_id'] = order['remote_id'].nil? ? 'NULL' : order['remote_id']
      order['uuid'] = UUID::Type.new.quoted_id(order['uuid'])
      "(#{order['id']}, #{order['uuid']}, #{order['remote_id']}, " \
      "'#{order['bid']}', '#{order['ask']}', '#{order['market_id']}', " \
      "#{order['price']}, #{order['volume']}, #{order['origin_volume']}, " \
      "#{order['maker_fee']}, #{order['taker_fee']}, #{order['state']}, " \
      "'#{order['type']}', #{order['member_id']}, '#{order['ord_type']}', " \
      "#{order['locked']}, #{order['origin_locked']}, #{order['funds_received']}, " \
      "#{order['trades_count']}, '#{order['created_at']}', '#{order['updated_at']}')"
    end
  end

  namespace :liabilities do
    desc 'Compact liabilities using Stored Procedure'
    task :compact_orders, %i[min_time max_time] => [:environment] do |_, args|
      Job.execute('compact_orders') do
        # Execute Stored Procedure for Liabilities compacting
        # Example:
        # Current date: "2020-07-30 16:39:15"
        # min_time: "2020-07-23 00:00:00"
        # max_time: "2020-07-24 00:00:00"
        # Compact liabilities beetwen: "2020-07-23 00:00:00" and "2020-07-24 00:00:00"
        args.with_defaults(min_time: (Time.now - 1.week).beginning_of_day.to_s(:db),
                          max_time: (Time.now - 6.day).beginning_of_day.to_s(:db))
        result = ActiveRecord::Base.connection.exec_query("call compact_orders('#{args.min_time}', '#{args.max_time}', @pointer, @counter)")
        ActiveRecord::Base.clear_active_connections!
        result
      end
    end
  end
end
