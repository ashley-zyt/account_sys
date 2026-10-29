# == Schema Information
#
# Table name: error_screenshots
#
#  id                                                                      :bigint           not null, primary key
#  error_msg(错误信息)                                                     :text(65535)
#  ref(业务透传标识（MoveTask:123 / Account:789 等）)                      :string(255)
#  screenshot_url(截图 OSS URL)                                            :string(255)
#  task_type(任务类型（nurture/fetch/send_message/check_reply/评论/发布）) :string(255)
#  created_at                                                              :datetime         not null
#  updated_at                                                              :datetime         not null
#  account_id(账号ID（可空）)                                              :bigint
#  browser_id(浏览器ID（可空）)                                            :bigint
#
# Indexes
#
#  index_error_screenshots_on_account_id  (account_id)
#  index_error_screenshots_on_created_at  (created_at)
#  index_error_screenshots_on_ref         (ref)
#  index_error_screenshots_on_task_type   (task_type)
#
class ErrorScreenshot < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :browser, optional: true

  def self.record!(ref:, task_type:, error_msg:, screenshot_url:, account_id: nil, browser_id: nil)
    return nil if screenshot_url.blank?
    create!(ref: ref, task_type: task_type, account_id: account_id, browser_id: browser_id,
            error_msg: error_msg, screenshot_url: screenshot_url)
  rescue => e
    Rails.logger.error "[ErrorScreenshot] 记录失败 ref=#{ref}: #{e.message}"
    nil
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id ref task_type account_id browser_id error_msg screenshot_url created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account browser]
  end
end
