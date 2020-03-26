# Модели
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class PromoMessage < ApplicationRecord
end

class User < ApplicationRecord
  has_many :ads
  scope :recent, -> { order('created_at DESC') }

  scope :published_one_ad, -> do
    joins(:ads).group('ads.user_id').where('published_ads_count = 1')
  end
end

class Ad < ApplicationRecord
  scope :published_between, ->(date_from_str, date_to_str) do
    begin
      date_from = Date.parse(date_from_str)
      date_to = Date.parse(date_to_str)

      where(<<-SQL, date_from, date_to)
        published_at BETWEEN ? AND ?
      SQL
    rescue TypeError, ArgumentError
      none
    end
  end
end




# Контроллеры
class PromoMessagesController < ApplicationController
  def new
    @message = PromoMessage.new
    @users = get_recent_users_for_date_period.page(params[:page])
  end

  def create
    @message = PromoMessage.new(promo_message_params)
    recipients = get_recent_users_for_date_period.pluck(:phone)

    if @message.save && send_message(recipients)
      redirect_to promo_messages_path, notice: "Messages Sent Successfully!"
    end
  end

  def download_csv
    users = get_recent_users_for_date_period
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

    def get_recent_users_for_date_period
      if params[:date_from].present? && params[:date_to].present?
        User.recent.published_one_ad.
          merge(Ad.published_between(params[:date_from], params[:date_to]))
      else
        User.none
      end
    end

    def promo_message_params
      params.permit(:body, :date_from, :date_to)
    end
end
