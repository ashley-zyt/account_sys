module Api
  module V1
    class KolsController < ApplicationController
      skip_before_action :verify_authenticity_token

      def fetch_conversation
        conversation = Conversation.includes(:kol, :kol_platform_account, :account)
                                   .where(status: [0, 1, 2])
                                   .order(created_at: :asc)
                                   .first

        if conversation
          latest_message = conversation.conversation_messages.order(sent_at: :desc).first

          response_data = {
            conversation_id: conversation.id,
            kol_name: conversation.kol&.kol_name,
            kol_platform: conversation.kol_platform_account&.platform,
            kol_profile_url: conversation.kol_platform_account&.profile_url,
            status: conversation.status,
            status_text: conversation.status.humanize,
            latest_message_content: latest_message&.content || conversation.latest_message,
            latest_message_time: latest_message&.sent_at || conversation.last_message_at,
            account_platform: conversation.account&.platform,
            browser_name: conversation.account&.browser&.name
          }

          render json: {
            success: true,
            data: response_data
          }
        else
          render json: {
            success: false,
            message: "没有找到符合条件的会话"
          }
        end
      rescue => e
        render json: {
          success: false,
          message: "获取会话失败：#{e.message}"
        }
      end

      def get_latest_message
        conversation_id = params[:conversation_id]

        if conversation_id.blank?
          return render json: {
            success: false,
            message: "缺少会话ID参数"
          }
        end

        conversation = Conversation.find_by(id: conversation_id)

        if conversation
          latest_message = conversation.conversation_messages.order(sent_at: :desc).first

          if latest_message
            response_data = {
              conversation_id: conversation.id,
              sender_type: latest_message.sender_type,
              content: latest_message.content,
              sent_at: latest_message.sent_at,
              status: latest_message.status
            }
          else
            response_data = {
              conversation_id: conversation.id,
              sender_type: nil,
              content: conversation.latest_message,
              sent_at: conversation.last_message_at,
              status: nil
            }
          end

          render json: {
            success: true,
            data: response_data
          }
        else
          render json: {
            success: false,
            message: "会话不存在"
          }
        end
      rescue => e
        render json: {
          success: false,
          message: "获取消息失败：#{e.message}"
        }
      end
    end
  end
end