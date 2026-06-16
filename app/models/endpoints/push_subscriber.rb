class Endpoints::PushSubscriber < NonCrudEndpoints
  # vapid_public_key is public — no authentication required.
  public_action :vapid_public_key

  self.desc 'PushSubscriber', :vapid_public_key, {
    get: {
      summary: 'Returns the VAPID public key for browser push subscription',
      parameters: [],
      responses: {
        '200' => {
          description: 'VAPID public key',
          content: {
            'application/json' => {
              schema: {
                type: 'object',
                properties: {
                  vapid_public_key: { type: 'string' }
                }
              }
            }
          }
        }
      }
    }
  }

  def vapid_public_key(params)
    key = ThecoreSettings::Setting.where(ns: :vapid, key: :public_key).pluck(:raw).first
    [{ vapid_public_key: key }, 200]
  end

  self.desc 'PushSubscriber', :subscribe, {
    post: {
      summary: 'Register or update a push subscription for the current user',
      parameters: [],
      responses: {
        '200' => { description: 'Updated subscriber' },
        '201' => { description: 'Created subscriber' }
      }
    }
  }

  def subscribe(params)
    user = User.find(params[:current_user_id])
    subscriber = PushSubscriber.subscribe_for(
      user,
      endpoint: params[:endpoint],
      p256dh: params[:p256dh],
      auth: params[:auth],
      user_agent: params[:user_agent]
    )
    status = subscriber.previously_new_record? ? 201 : 200
    [subscriber, status]
  rescue ActiveRecord::RecordInvalid => e
    [{ error: e.message }, 422]
  end

  self.desc 'PushSubscriber', :send_push, {
    post: {
      summary: 'Send a Web Push notification to a specific subscriber',
      parameters: [],
      responses: {
        '201' => { description: 'Message created and dispatched' },
        '422' => { description: 'Validation error' },
        '404' => { description: 'Subscriber not found' }
      }
    }
  }

  def send_push(params)
    subscriber = PushSubscriber.active.find_by(id: params[:push_subscriber_id])
    return [{ error: 'Subscriber not found' }, 404] unless subscriber
    message = subscriber.push_messages.build(
      title: params[:title],
      body: params[:body],
      url: params[:url],
      icon: params[:icon]
    )
    unless message.save
      return [{ error: message.errors.full_messages.join(', ') }, 422]
    end
    ThecoreBackendCommons::PushNotificationService.dispatch(subscriber, message)
    [message, 201]
  rescue => e
    [{ error: e.message }, 500]
  end

  self.desc 'PushSubscriber', :acknowledge, {
    post: {
      summary: 'Mark a push message as received or read',
      parameters: [],
      responses: {
        '200' => { description: 'Message updated' },
        '404' => { description: 'Message not found' }
      }
    }
  }

  def acknowledge(params)
    message = PushMessage.find_by(id: params[:push_message_id])
    return [{ error: 'Message not found' }, 404] unless message

    now = Time.current
    message.update!(received_at: now) if params[:received] && message.received_at.nil?
    message.update!(read_at: now) if params[:read] && message.read_at.nil?
    [message, 200]
  rescue ActiveRecord::RecordInvalid => e
    [{ error: e.message }, 422]
  end
end
