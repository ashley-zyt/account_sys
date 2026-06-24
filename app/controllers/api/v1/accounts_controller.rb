module Api
  module V1
    # 账号数据接口
    # 提供账号信息查询
    class AccountsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/accounts
      # 获取正常账号列表
      # 查询参数:
      #   theme - 按主题筛选（可选）
      #   platform - 按平台筛选（可选）
      #   work_type - 按工作模式筛选（可选）
      def index
        accounts = Account.active

        # 按主题筛选
        if params[:theme].present?
          accounts = accounts.where(theme: params[:theme])
        end

        # 按平台筛选
        if params[:platform].present?
          accounts = accounts.where(platform: params[:platform])
        end

        # 按工作模式筛选
        if params[:work_type].present?
          accounts = accounts.where(work_type: params[:work_type])
        end

        # 按最后使用时间排序（最久未使用的优先）
        accounts = accounts.order('last_used_at ASC NULLS FIRST')

        render json: {
          code: 200,
          msg: '查询成功',
          data: {
            total: accounts.count,
            accounts: accounts.map { |account|
              {
                id: account.id,
                account_name: account.account_name,
                source_url: account.source_url,
                theme: account.theme,
                platform: account.platform,
                work_type: account.work_type,
                status: account.status,
                last_used_at: account.last_used_at&.strftime('%Y-%m-%d %H:%M:%S'),
                created_at: account.created_at.strftime('%Y-%m-%d %H:%M:%S')
              }
            }
          }
        }
      end

      # GET /api/v1/accounts/:id
      # 获取指定账号详情
      def show
        account = Account.find_by(id: params[:id])
        if account.blank?
          return render json: { code: 404, msg: '账号不存在' }, status: :not_found
        end

        render json: {
          code: 200,
          msg: '查询成功',
          data: {
            id: account.id,
            account_name: account.account_name,
            source_url: account.source_url,
            theme: account.theme,
            platform: account.platform,
            work_type: account.work_type,
            status: account.status,
            browser_id: account.browser_id,
            last_used_at: account.last_used_at&.strftime('%Y-%m-%d %H:%M:%S'),
            created_at: account.created_at.strftime('%Y-%m-%d %H:%M:%S'),
            updated_at: account.updated_at.strftime('%Y-%m-%d %H:%M:%S')
          }
        }
      end

      # GET /api/v1/accounts/by_name
      # 根据账号名查询
      def by_name
        if params[:account_name].blank?
          return render json: { code: 400, msg: 'account_name 参数不能为空' }, status: :bad_request
        end

        account = Account.find_by(account_name: params[:account_name])
        if account.blank?
          return render json: { code: 404, msg: '账号不存在' }, status: :not_found
        end

        render json: {
          code: 200,
          msg: '查询成功',
          data: {
            id: account.id,
            account_name: account.account_name,
            source_url: account.source_url,
            theme: account.theme,
            platform: account.platform,
            status: account.status
          }
        }
      end

      # GET /api/v1/accounts/themes
      # 获取所有主题列表
      def themes
        themes = Account.active.distinct.pluck(:theme).compact.sort

        render json: {
          code: 200,
          msg: '查询成功',
          data: {
            themes: themes
          }
        }
      end
    end
  end
end