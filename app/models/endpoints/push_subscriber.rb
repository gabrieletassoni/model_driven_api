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
      summary: 'Send Web Push to one subscriber (push_subscriber_id) or many (push_subscriber_ids array, async).',
      parameters: [],
      responses: {
        '201' => { description: 'Single: message JSON. Bulk: { created: [...], failed: [...] }' },
        '422' => { description: 'Validation error' },
        '404' => { description: 'Subscriber not found (single mode only)' }
      }
    }
  }

  def send_push(params)
    return [{ error: 'title is required' }, 422] if params[:title].blank?
    return [{ error: 'body is required' }, 422] if params[:body].blank?

    if params[:push_subscriber_ids].present?
      send_push_bulk(params)
    else
      send_push_single(params)
    end
  rescue => e
    [{ error: e.message }, 500]
  end

  self.desc 'PushSubscriber', :broadcast_push, {
    post: {
      summary: 'Send Web Push to all active subscribers.',
      parameters: [],
      responses: {
        '201' => { description: '{ enqueued: N } — number of jobs enqueued' },
        '422' => { description: 'Validation error (title or body missing)' }
      }
    }
  }

  def broadcast_push(params)
    return [{ error: 'title is required' }, 422] if params[:title].blank?
    return [{ error: 'body is required' }, 422] if params[:body].blank?

    broadcast_push_all(params)
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
    [message.as_json(PushMessage.json_attrs), 200]
  rescue ActiveRecord::RecordInvalid => e
    [{ error: e.message }, 422]
  end

  private

  def send_push_single(params) # rubocop:disable Metrics/MethodLength
    subscriber = PushSubscriber.active.find_by(id: params[:push_subscriber_id])
    return [{ error: 'Subscriber not found' }, 404] unless subscriber

    message = subscriber.push_messages.build(
      title: params[:title],
      body: params[:body],
      url: params[:url],
      icon: params[:icon]
    )
    return [{ error: message.errors.full_messages.join(', ') }, 422] unless message.save

    ThecoreBackendCommons::PushNotificationService.dispatch(subscriber, message)
    [message.as_json(PushMessage.json_attrs), 201]
  end

  def broadcast_push_all(params) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    active_ids = PushSubscriber.active.pluck(:id)
    return [{ enqueued: 0 }, 201] if active_ids.empty?

    now = Time.current
    records = active_ids.map do |sub_id|
      {
        push_subscriber_id: sub_id,
        title: params[:title],
        body: params[:body],
        url: params[:url].presence,
        icon: params[:icon].presence,
        message_type: params[:message_type].presence || 'communication',
        sender_user_id: params[:current_user_id].presence,
        created_at: now,
        updated_at: now
      }
    end

    returning_cols = %w[id push_subscriber_id title body url icon
                        message_type sent_at received_at read_at
                        created_at updated_at sender_user_id]
    result = PushMessage.insert_all(records, returning: returning_cols)

    created = result.to_a
    created.each { |r| PushDispatchJob.perform_later(r['id']) }

    [{ enqueued: created.length }, 201]
  end

  def send_push_bulk(params) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    ids = Array(params[:push_subscriber_ids]).map(&:to_i).uniq
    valid_ids = PushSubscriber.active.where(id: ids).pluck(:id)
    failed = ids - valid_ids

    return [{ created: [], failed: failed }, 201] if valid_ids.empty?

    now = Time.current
    records = valid_ids.map do |sub_id|
      {
        push_subscriber_id: sub_id,
        title: params[:title],
        body: params[:body],
        url: params[:url].presence,
        icon: params[:icon].presence,
        message_type: params[:message_type].presence || 'communication',
        sender_user_id: params[:sender_user_id].presence,
        created_at: now,
        updated_at: now
      }
    end

    returning_cols = %w[id push_subscriber_id title body url icon
                        message_type sent_at received_at read_at
                        created_at updated_at sender_user_id]
    result = PushMessage.insert_all(records, returning: returning_cols)

    created = result.to_a
    created.each { |r| PushDispatchJob.perform_later(r['id']) }

    [{ created: created, failed: failed }, 201]
  end
end
