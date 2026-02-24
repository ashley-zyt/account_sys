class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  
  def self.transaction_with_lock(&block)
    transaction do
      lock!
      yield
    end
  end
end
