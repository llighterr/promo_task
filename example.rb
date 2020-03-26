# Модели
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class PromoMessage < ApplicationRecord
end

class User < ApplicationRecord
  has_many :ads
  scope :recent, -> { order("created_at DESC") }
end

class Ad < ApplicationRecord
end




# Контроллеры
class PromoMessagesController < ApplicationController
  attr_reader :provider

  def new
    @message = PromoMessage.new
    if params[:date_from].present? && params[:date_to].present?
      get_users
    end
  end

  def create
    @message = PromoMessage.new(promo_message_params)

    users = get_users
    recipients = []
    users.each do |user|
      recipients << user.phone
    end

    if @message.save && send_message(recipients)
      redirect_to promo_messages_path, notice: "Messages Sent Successfully!"
    end
  end

  def download_csv
    users = get_users
    send_data to_csv(users), filename: "promotion-users-#{Time.zone.today}.csv"
  end

  private

    def to_csv(data)
      attributes = %w(id phone name)
      CSV.generate(headers: true) do |csv|
        csv << attributes
        data.each do |user|
          csv << attributes.map { |attr| user.send(attr) }
        end
      end
    end

    def send_message(recipients)
      recipients.each do |r|
        PromoMessagesSendJob.perform_later(r)
      end
    end

    def get_users
      @users = User.recent.joins(:ads).group("ads.user_id").where("`published_ads_count` = 1").
        where("published_at Between ? AND ?", Date.parse(params[:date_from]), Date.parse(params[:date_to])).page(params[:page])
    end

    def promo_message_params
      params.permit(:body, :date_from, :date_to)
    end
end
