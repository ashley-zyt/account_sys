# == Schema Information
#
# Table name: message_templates
#
#  id                      :bigint           not null, primary key
#  content(模板内容)       :text(65535)      not null
#  language(语言)          :string(255)      default("en")
#  platform(平台)          :integer          not null
#  template_type(模板类型) :integer          not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_message_templates_on_platform       (platform)
#  index_message_templates_on_template_type  (template_type)
#
class MessageTemplate < ApplicationRecord
  enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		instagram: 5
	}

  enum :template_type, {
    first_contact: 0,
    follow_up: 1,
    reply: 2,
    cooperation: 3,
    closing: 4
  }

  validates :platform, presence: true
  validates :template_type, presence: true
  validates :content, presence: true
end
