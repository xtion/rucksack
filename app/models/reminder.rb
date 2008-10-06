require 'chronic'

class Reminder < ActiveRecord::Base
    belongs_to :created_by, :class_name => 'User', :foreign_key => 'created_by_id'
    belongs_to :updated_by, :class_name => 'User', :foreign_key => 'updated_by_id'
  
    @@repeat_lookup = {:never => 0, :yearly => 1, :monthly => 2, :fortnightly => 3, :weekly => 4, :daily => 5}
    @@repeat_id_lookup = @@repeat_lookup.invert

    after_create   :process_create
    before_update  :process_update_params
    before_destroy :process_destroy
    
    def process_create
      ApplicationLog.new_log(self, self.created_by, :add)
    end
    
    def process_update_params
      ApplicationLog.new_log(self, self.updated_by, :edit)
    end
    
    def process_destroy
      ApplicationLog.new_log(self, self.updated_by, :delete)
    end
    
    def page
      nil
    end
    
    def object_name
        self.content
    end
    
    def friendly_at_time
        @cached_friendly_time || self.at_time.to_s
    end
    
    def friendly_at_time=(value)
        @cached_friendly_time = value
        ctime = Chronic.parse(value, :now => Time.zone.now)
        # TODO: possible to extract subject from query?
        
        if !ctime.nil?
            # re-interpret time in local zone
            ctime = Time.zone.local(ctime.year, ctime.mon, ctime.day, ctime.hour, ctime.min, ctime.sec)
        else
            # Default to now + 3 hours
            ctime = (Time.zone.now + (60*60*3))
        end
        
        self.at_time = ctime
        self.content = value
    end
    
    def snooze(interval={:minutes => 15})
        self.at_time = Time.zone.now.advance(interval)
    end
  
    def friendly_repeat
        "reminder_repeat_#{self.repeat}".to_sym.l
    end
  
    def repeat
        @@repeat_id_lookup[self.repeat_id]
    end
  
    def repeat=(val)
        self.repeat_id = @@repeat_lookup[val.to_sym]
    end
    
    def expired?
        self.sent and self.at_time <= 2.days.ago
    end
    
    def done?
        self.at_time <= Time.zone.now
    end
    
    def repeatable?
        self.repeat_id > 0
    end

  # Common permissions

  def self.can_be_created_by(user)
    user.member_of_owner?
  end
  
  def can_be_edited_by(user)
   return (user.is_admin or user.id == self.created_by_id)
  end
  
  def can_be_deleted_by(user)
   return (user.is_admin or user.id == self.created_by_id)
  end
  
  def can_be_seen_by(user)
   return (user.is_admin or self.created_by_id == user.id)
  end
    
    def dispatch_notification
        #puts ""
        Notifier.deliver_reminder(self)
        self.sent = true
    end
    
    def self.dispatch_and_clean
        now = Time.now.utc
        
        Reminder.find(:all, :conditions => ['at_time <= ?', now], :order => 'at_time ASC').each do |reminder|
            if reminder.expired?
                #puts "expired, remove!"
                reminder.destroy
            elsif !reminder.sent
                reminder.dispatch_notification
                
                if reminder.repeatable?
                    interval = nil
                    case reminder.repeat
                        when :yearly
                            interval = {:years => 1}
                        when :monthly
                            interval = {:months => 1}
                        when :fortnightly
                            interval = {:weeks => 2}
                        when :weekly
                            interval = {:weeks => 1}
                        when :daily
                            interval = {:days => 1}
                    end
                    
                    unless interval.nil?
                        reminder.at_time = reminder.at_time.advance(interval) unless interval.nil?
                    end
                end
                
                reminder.save
            end
        end
    end
    
    def self.select_repeat
        @@repeat_lookup.keys.map do |key|
            ["reminder_repeat_#{self.repeat}".to_sym.l, key]
        end
    end
  
  # Accesibility
  
  attr_accessible :repeat, :friendly_at_time, :content, :at_time
end
