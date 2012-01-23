class Activity
  include Streama::Activity
  
  activity :new_enquiry do
    actor :user, :cache => [:full_name]
    object :enquiry, :cache => [:comment]
    act_target :listing, :cache => [:title]
  end
  
  activity :new_enquiry_without_cache do
    actor :user
    object :enquiry
    act_target :listing
  end
  
  activity :new_comment do
    actor :user, :cache => [:full_name]
    object :listing
  end
    
end