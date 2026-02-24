# app/services/theme_config.rb
require 'yaml'
require 'active_support/concern'

class ThemeConfig
	CONFIG_PATH = Rails.root.join('config/theme_config.yml')

	class << self
		def config
			@config ||= load_config
		end

		def reload!
			@config = load_config
		end

		# 根据来源账号主页链接匹配主题
		def match_theme(source_url)
			config['themes']&.each do |theme|
				theme['source_urls']&.each do |url|
					return theme['name'] if source_url.include?(url) # 简单包含匹配，可调整为正则
				end
			end
			nil
		end

		# 从主题标题池中随机选择一个标题（可扩展变量替换）
		def random_title(theme_name)
			theme = config['themes']&.find { |t| t['name'] == theme_name }
			return nil unless theme && theme['titles'].present?

			template = theme['titles'].sample
		end
	end

	private_class_method 
	def self.load_config
		return {} unless File.exist?(CONFIG_PATH)
		YAML.load_file(CONFIG_PATH).deep_stringify_keys
	end
end