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

# Декораторы
require 'csv'

class UserDecorator < SimpleDelegator
  def self.to_csv
    CSV.generate(headers: true) do |csv|
      csv << column_names
      find_each do |user|
        csv << user.attributes.values
      end
    end
  end
end

# Интеракторы
class SendPromoMessageToUsers
  delegate :params, to: :@view

  def initialize(view:, users:)
    @view = view
    @users = users
    @errors = []
  end

  def call
    save_message
    send_message

    if errors.present?
      { errors: errors }
    else
      { success: 'Message was saved successfully, users will receive it shortly' }
    end
  end

  private

  attr_reader :errors, :users

  def save_message
    message = PromoMessage.new(promo_message_params)
    message.save
    errors.concat(message.errors.full_messages)
  end

  def promo_message_params
    params.permit(:body, :date_from, :date_to)
  end

  def send_message
    recipient_phones.each do |phone|
      PromoMessagesSendJob.perform_later(phone)
    end
  end

  def recipient_phones
    users.pluck(:phone)
  end
end

# Контроллеры
class PromoMessagesController < ApplicationController
  def new
    @message = PromoMessage.new
    @users = get_recent_users_for_date_period.page(params[:page])
  end

  def create
    result = SendPromoMessageToUsers.new(
      view: view_context,
      users: get_recent_users_for_date_period
    )

    if result[:success]
      redirect_to promo_messages_path, notice: result[:success]
    else
      render action: :new, alert: result[:errors].join(' ')
    end
  end

  def download_csv
    users = get_recent_users_for_date_period
    send_data UserDecorator.new(users).to_csv,
      filename: "promotion-users-#{Time.zone.today}.csv"
    # NOTE: if you experience memory leaks using #send_data, try to release
    # memory faster adding `GC.start` after this action.
    # For additional details please check https://www.reddit.com/r/rails/comments/8dy41g/huge_memory_consumption_exporting_data_to_excelcsv/
  end

  private

  def get_recent_users_for_date_period
    if params[:date_from].present? && params[:date_to].present?
      User.recent.published_one_ad.
        merge(Ad.published_between(params[:date_from], params[:date_to]))
    else
      User.none
    end
  end
end
