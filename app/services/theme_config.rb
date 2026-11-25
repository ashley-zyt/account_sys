# app/services/theme_config.rb
# 对标账号匹配 + 标题池，统一读 Theme 表（后台可自助维护，不再依赖 theme_config.yml）。

class ThemeConfig
	class << self
		# 根据来源账号主页链接匹配主题（返回第一个命中主题，保持旧接口兼容）。
		def match_theme(source_url)
			match_themes(source_url).first
		end

		# 根据来源账号主页链接匹配所有主题（一个对标账号可归属多个主题）。
		# 读 Theme 表（后台可自助维护对标账号），返回命中的主题名数组（去重）。
		def match_themes(source_url)
			return [] if source_url.blank?

			Theme.where.not(source_accounts: [nil, '']).each_with_object([]) do |theme, acc|
				theme.source_accounts_array.each do |url|
					if source_url.include?(url)
						acc << theme.name
						break
					end
				end
			end.uniq
		end

		# 从主题标题池中随机选择一个标题。
		# 读 Theme 表的 titles。
		def random_title(theme_name)
			theme = Theme.find_by(name: theme_name)
			return nil unless theme

			theme.titles_array.sample
		end
	end
end
