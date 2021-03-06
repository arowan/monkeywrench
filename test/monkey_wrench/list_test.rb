$:.unshift File.expand_path("..", File.dirname(__FILE__))
require "test_helper"

class MonkeyWrench::ListTest < Test::Unit::TestCase
  context "finding a list" do
    setup do
      setup_config
    end
    context "finding a list by id" do
      should "find a list by id" do
        mock_chimp_post(:lists)
        list = MonkeyWrench::List.find("my-list-id")
        expected = MonkeyWrench::List.new(:id => "my-list-id")
        assert_equal expected, list
      end
      should "return nil if the list doesn't exist" do
        mock_chimp_post(:lists)
        list = MonkeyWrench::List.find("imaginary-list-id")
        assert_equal nil, list
      end
    end
    
    context "finding a list by name" do
      should "find a single list by name" do
        mock_chimp_post(:lists)
        list = MonkeyWrench::List.find_by_name("A test list")
        assert_equal MonkeyWrench::List.new(:id => "my-list-id"), list
      end

      should "return nil if the list doesn't exist" do
        mock_chimp_post(:lists)
        list = MonkeyWrench::List.find_by_name("An imaginary list")
        assert_equal nil, list
      end
    end
    
    context "finding all lists" do
      setup do
        setup_config
      end
      should "return an empty array if no lists exist" do
        mock_chimp_post(:lists, {}, true, "listsEmpty")
        lists = MonkeyWrench::List.find_all
        assert_equal [], lists
      end
      
      should "return an array of lists" do
        mock_chimp_post(:lists)
        lists = MonkeyWrench::List.find_all
        expected = [MonkeyWrench::List.new(:id => "my-list-id")]
        assert_equal expected, lists
      end
    end
    
    context "caching" do
      setup do
        setup_config
      end
      
      should "be cleared when #clear! is called" do
        mock_chimp_post(:lists)
        MonkeyWrench::List.find_all
        MonkeyWrench::List.clear!
        mock_chimp_post(:lists, {}, true, "listsEmpty")
        lists = MonkeyWrench::List.find_all
        assert_equal [], lists
      end
      
      should "cache the list of lists" do
        mock_chimp_post(:lists)
        MonkeyWrench::List.find_all
        mock_chimp_post(:lists, {}, true, "listsEmpty")
        lists = MonkeyWrench::List.find_all
        expected = [MonkeyWrench::List.new(:id => "my-list-id")]
        assert_equal expected, lists
      end
    end
  end
  
  context "subscribing to a list" do
    setup do
      setup_config
      mock_chimp_post(:lists)
      @list = MonkeyWrench::List.find_by_name("A test list")
    end

    context "multiple subscribers at once" do
      should "subscribe users" do
        form_params = {
          :batch => [{'EMAIL' => "mail@chimp.com", 
                       'TYPE' => "html"
                     }],
          :id => "my-list-id"}
        mock_chimp_post(:listBatchSubscribe, form_params)

        subscribers = [{:email => "mail@chimp.com", :type => :html}]
        expected = {:success => 1, :errors => []}
        assert_equal expected, @list.subscribe(subscribers)
      end

      should "split more than one thousand subscribers into batches" do
        subscribers = (1..1004).map do |i|
          {:email => "mail#{i}@chimp.com", :type => :html}
        end
        response_sequence = [
                             {:body => canned_response('listBatchSubscribe1000_success.json'), :headers => {'Content-Type' => 'application/json'}},
                             {:body => canned_response('listBatchSubscribe4_success.json'), :headers => {'Content-Type' => 'application/json'}}
                            ]
        stub_request(:post, uri_for_remote_method('listBatchSubscribe')).to_return(response_sequence)
        expected = {:success => 1004, :errors => []}      
        assert_equal expected, @list.subscribe(subscribers)
      end

      should "send welcome email" do
        form_params = {:merge_vars => {"FOO" => "bar"}, :id => "my-list-id", 
                       :email_address => "mail@chimp.com", :type => "html",
                       :send_welcome => "true"}
        mock_chimp_post(:listSubscribe, form_params)

        subscribers = [{:email => "mail@chimp.com", :type => :html, :foo => "bar"}]
        expected = {:success => 1, :errors => []}
        assert_equal expected, @list.subscribe(subscribers, :send_welcome => true)
      end

      should "opt-out from list" do
      end

      should "collate errors" do
        form_params = {
          :batch => [
                     {'EMAIL' => "mail@chimp.com", 'TYPE' => 'html'},
                     {'EMAIL' => "bademail@badmail", 'TYPE' => 'html'}
                    ],
          :id => "my-list-id"}
        mock_chimp_post(:listBatchSubscribe, form_params, true, 'listBatchSubscribe_with_error')

        subscribers = [
                       {:email => "mail@chimp.com", :type => :html},
                       {:email => "bademail@badmail", :type => :html}
                      ]
        actual = @list.subscribe(subscribers)
        assert_equal 1, actual[:success]
        assert_equal 'Invalid Email Address: bademail@badmail', actual[:errors][0].message
        assert_equal 502, actual[:errors][0].code
        assert_equal 'Invalid_Email', actual[:errors][0].type
        assert_equal({"EMAIL_TYPE"=>"html", "EMAIL"=>"bademail@badmail"}, actual[:errors][0].row)
      end
    end
    
    context "a single subscriber" do
      should "subsbscibe a user" do
        form_params = { :type=> "html", 
                        :update_existing => "true", 
                        :merge_vars => {'MY_DATE'=>"20090101", 'FNAME' => 'Joe'},
                        :replace_interests => "false", 
                        :double_optin => "false", 
                        :id => "my-list-id",
                        :send_welcome => "true",
                        :email_address => "mail@chimp.com" }
        mock_chimp_post(:listSubscribe, form_params)

        params = { :type => :html,
                   :double_optin => false,
                   :update_existing => true,
                   :replace_interests => false,
                   :send_welcome => true,
                   :fname => "Joe",
                   :my_date => "20090101" 
                   }
        
        expected = {:success => 1, :errors => []}      
        assert_equal expected, @list.subscribe("mail@chimp.com", params)
      end
    end    
  end

  context "unsubscribing to a list" do
    setup do
      setup_config
      mock_chimp_post(:lists)
      @list = MonkeyWrench::List.find_by_name("A test list")
    end
    
    context "multiple subscribers at once" do
      should "unsubscribe" do
        form_params = {"emails" => ["mail@chimp.com"], :id => "my-list-id"}      
        mock_chimp_post(:listBatchUnsubscribe, form_params)
        subscribers = ["mail@chimp.com"]
      
        expected = {:success => 1, :errors => []}
        assert_equal expected, @list.unsubscribe(subscribers)
      end
      
      should "delete subscriber" do
        form_params = {"emails" => ["mail@chimp.com"], :id => "my-list-id",
                       :delete_member => "true"}
        mock_chimp_post(:listBatchUnsubscribe, form_params)
        subscribers = ["mail@chimp.com"]
      
        expected = {:success => 1, :errors => []}
        assert_equal expected, @list.unsubscribe(subscribers, :delete_member => true)
      end
      
      should "send goodbye" do
        form_params = {"emails" => ["mail@chimp.com"], :id => "my-list-id",
                       :send_goodbye => "true"}
        mock_chimp_post(:listBatchUnsubscribe, form_params)
        subscribers = ["mail@chimp.com"]
      
        expected = {:success => 1, :errors => []}
        assert_equal expected, @list.unsubscribe(subscribers, :send_goodbye => true)
      end
      
      should "send unsubscribe notification" do
        form_params = {"emails" => ["mail@chimp.com"], :id => "my-list-id",
                       :send_notify => "true"}
        mock_chimp_post(:listBatchUnsubscribe, form_params)
        subscribers = ["mail@chimp.com"]
      
        expected = {:success => 1, :errors => []}
        assert_equal expected, @list.unsubscribe(subscribers, :send_notify => true)
      end
    end
    
    context "a single subscriber" do
      should "unsubscribe" do
        form_params = { "emails" => ["mail@chimp.com"], :id => "my-list-id" }
        mock_chimp_post(:listBatchUnsubscribe, form_params)

        expected = {:success => 1, :errors => []}      
        assert_equal expected, @list.unsubscribe("mail@chimp.com")
      end
    end
  end
  
  context "opting out of a list" do
    setup do
      setup_config
      mock_chimp_post(:lists)
      @list = MonkeyWrench::List.find_by_name("A test list")
    end
    
    context "multiple subscribers at once" do
      should "opt out" do
        form_params = { :batch => [
                                   {'EMAIL' => "mail@chimp.com"},
                                   {'EMAIL' => 'foo@bar.com'}
                                  ], :id => "my-list-id"
                      }
        mock_chimp_post(:listBatchSubscribe, form_params)
        form_params = { :emails => ["mail@chimp.com", "foo@bar.com"], :id => "my-list-id",
                        :send_goodbye => "false", :send_notify => "false" }
        mock_chimp_post(:listBatchUnsubscribe, form_params)
        subscribers = ["mail@chimp.com", "foo@bar.com"]
      
        expected = {:success => 1, :errors => []}
        assert_equal expected, @list.opt_out(subscribers)
      end
    end
    
    context "a single subscriber" do
      should "opt out" do
        form_params = { :batch => [{"EMAIL" => "mail@chimp.com"}], :id => "my-list-id" }
        mock_chimp_post(:listBatchSubscribe, form_params)
        form_params = { :emails => ["mail@chimp.com"], :id => "my-list-id", 
                        :send_goodbye => "false", :send_notify => "false"}
        mock_chimp_post(:listBatchUnsubscribe, form_params)

        expected = {:success => 1, :errors => []}      
        assert_equal expected, @list.opt_out("mail@chimp.com")
      end
    end
  end

  context "retrieving member information" do
    setup do
      setup_config
      mock_chimp_post(:lists)
      @list = MonkeyWrench::List.find_by_name("A test list")
    end

    should "list members" do
      mock_chimp_post(:listMembers, :id => "my-list-id")

      expected = [
        MonkeyWrench::Member.new({"timestamp"=>"2009-11-12 15:46:20", "email"=>"david@email.com"}),
        MonkeyWrench::Member.new({"timestamp"=>"2009-11-12 15:52:52", "email"=>"julie@email.com"}) ]
      assert_equal expected, @list.members
    end

    should "iterate over all members" do
      response_sequence = %w{listMembers listMembers listMembers_none}.map do |fixture|
        {
          :body => canned_response("#{fixture}_success.json"),
          :headers => {'Content-Type' => 'application/json'}
        }
      end
      stub_request(:post, uri_for_remote_method('listMembers')).to_return(response_sequence)

      expected = [ 
                  MonkeyWrench::Member.new({"timestamp"=>"2009-11-12 15:46:20", "email"=>"david@email.com"}), 
                  MonkeyWrench::Member.new({"timestamp"=>"2009-11-12 15:52:52", "email"=>"julie@email.com"}),
                  MonkeyWrench::Member.new({"timestamp"=>"2009-11-12 15:46:20", "email"=>"david@email.com"}), 
                  MonkeyWrench::Member.new({"timestamp"=>"2009-11-12 15:52:52", "email"=>"julie@email.com"})
                 ]
      actual = []
      @list.each_member { |m| actual << m }
      assert_equal expected, actual
    end
  end

  context "updating members" do
    setup do
      setup_config
      mock_chimp_post(:lists)
      @list = MonkeyWrench::List.find_by_name("A test list")
    end

    should "accept single member's email address change as hash" do
      member = {:email => "foo@bar.com", :new_email => "bar@foo.com"}
      form_params = {:email_address => "foo@bar.com", 
                     :email => "foo@bar.com", 
                     :merge_vars => {"EMAIL" => 'bar@foo.com'},
                     :replace_interests => "true", :id => "my-list-id"}
      mock_chimp_post(:listUpdateMember, form_params)
      @list.update_members(member, :replace_interests => true)
    end

    should "accept single member's email address change as list" do
      members = [{:email => "foo@bar.com", :new_email => "bar@foo.com"}]
      form_params = {
        :email_address => "foo@bar.com", 
        :email => "foo@bar.com", 
        :merge_vars => {'EMAIL' => 'bar@foo.com'}, 
        :replace_interests => "true", :id => "my-list-id"
      }
      mock_chimp_post(:listUpdateMember, form_params)
      @list.update_members(members, :replace_interests => true)
    end

    should "update multiple members emails addresses" do
      members = [
                 {:email => "foo@bar.com", :new_email => "bar@foo.com"},
                 {:email => "spock@vulcan.com", :new_email => "sylar@heroes.com"}
                ]
      form_params = {
        :email_address => "foo@bar.com", 
        :email => "foo@bar.com", 
        :merge_vars => {"EMAIL" => 'bar@foo.com'},
        :replace_interests => "true", :id => "my-list-id"
      }
      mock_chimp_post(:listUpdateMember, form_params)
      form_params = {
        :email_address => "spock@vulcan.com", 
        :email => "spock@vulcan.com", 
        :merge_vars => {'EMAIL' => 'sylar@heroes.com'}, 
        :replace_interests => "true", :id => "my-list-id"
      }
      mock_chimp_post(:listUpdateMember, form_params)
      @list.update_members(members, :replace_interests => true)
    end
  end

  context "retrieving a members info" do
    setup do
      setup_config
      mock_chimp_post(:lists)
      @list = MonkeyWrench::List.find_by_name("A test list")
    end

    should "return the info" do
      form_params = {:email_address => "david@email.com", :id => "my-list-id"}
      mock_chimp_post(:listMemberInfo, form_params)
      member = @list.member("david@email.com")
      assert_equal "david@email.com", member.email
      assert_equal "html", member.email_type
      assert_equal "David", member.fname
      assert_equal ["freetrial", "tutorials"], member.interests
    end

    should "raise on error" do
      form_params = {:email_address => "david@email.com", :id => "my-list-id"}
      mock_chimp_post(:listMemberInfo, form_params, false)
      assert_raises(MonkeyWrench::Error) do
        @list.member("david@email.com")
      end
    end
  end

  context "checking for user subscription" do
    setup do
      setup_config
      mock_chimp_post(:lists)
      @list = MonkeyWrench::List.find_by_name("A test list")
    end

    should "return true if found" do
      form_params = {:email_address => "david@email.com", :id => "my-list-id"}
      mock_chimp_post(:listMemberInfo, form_params)
      assert @list.member?("david@email.com")
    end

    should "return false if not found" do
      form_params = {:email_address => "asdf-not-david@email.com", :id => "my-list-id"}
      mock_chimp_post(:listMemberInfo, form_params, false)
      assert !@list.member?("asdf-not-david@email.com")
    end
  end
end
