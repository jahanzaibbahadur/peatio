# frozen_string_literal: true

class Job < ApplicationRecord

  before_create { self.finished_at = Time.now }

  def self.execute(name)
    job = new(name: name, started_at: Time.now)
    result = yield
    job.pointer = result['pointer']
    job.counter = result['counter']
    job.error_code = 0
    job.save!
  rescue StandardError => e
    job.error_code = 1
    job.error_message = e.message
    job.save!
  end
end
