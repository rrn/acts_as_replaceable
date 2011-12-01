require 'spec_helper'

describe 'acts_as_dag' do
  before(:each) do
    [Material, Item, Person].each(&:destroy_all) # Because we're using sqlite3 and it doesn't support transactional specs (afaik)
  end

  describe "A saved record" do

    it "should raise an exception if more than one duplicate exists in the database" do
      insert_model(Material, :name => 'wood')
      insert_model(Material, :name => 'wood')
      lambda {Material.create! :name => 'wood'}.should raise_exception
    end

    it "should raise an exception when matching against multiple fields" do
      insert_model(Item, :identification_number => '1234', :holding_institution_id => 1)
      insert_model(Item, :identification_number => '1234', :holding_institution_id => 1)
      lambda {Item.create! :identification_number => '1234', :holding_institution_id => 1}.should raise_exception
    end
    
    it "should replace itself with an existing record by matching a single column" do
      Material.create! :name => 'wood'
      Material.create! :name => 'wood'
      Material.where(:name => 'wood').count.should == 1
    end

    it "should replace itself with an existing record by matching multiple columns" do
      Location.create! :country => 'Canada', :city => 'Vancouver'
      Location.create! :country => 'Canada', :city => 'Vancouver'
      Location.where(:country => 'Canada', :city => 'Vancouver').count.should == 1
    end

    it "should replace itself with an existing record by matching multiple columns and inheriting a column from the existing record" do
      a = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2,  :fingerprint => 'asdf'
      b = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2
      Item.where(:identification_number => '1234', :holding_institution_id => 1, :collection_id => 2).count.should == 1
      b.fingerprint.should == 'asdf'
    end

    it "should update the non-match, non-inherit fields of the existing record" do
      a = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2,  :fingerprint => 'asdf'
      b = Item.create! :name => 'Dip Stick', :identification_number => '1234', :holding_institution_id => 1, :collection_id => 2
      c = Item.where(:identification_number => '1234', :holding_institution_id => 1, :collection_id => 2)
      c.count.should == 1
      c.first.name.should == 'Dip Stick'
    end
    
    it "should correctly replace an existing record when a match value is nil" do
      a = Item.create! :name => 'Stick', :identification_number => '1234', :holding_institution_id => 1
      b = Item.create! :name => 'Dip Stick', :identification_number => '1234', :holding_institution_id => 1
      Item.where(:identification_number => '1234', :holding_institution_id => 1).count.should == 1
    end

    it "should replace itself with an existing record by performing case-insensitive matching on multiple columns" do
      Person.create! :first_name => 'John', :last_name => 'Doe'
      Person.create! :first_name => 'joHn', :last_name => 'doE'
      Person.where(:first_name => 'John', :last_name => 'Doe').count.should == 1

      Person.create! :first_name => 'Alanson', :last_name => 'Skinner'
      Person.create! :first_name => 'Alanson', :last_name => 'Skinner'
      Person.where(:first_name => 'Alanson', :last_name => 'Skinner').count.should == 1
    end
    
    it "should not replace an existing record with fields that were used to match" do
      Person.create! :first_name => 'joHn', :last_name => 'doE'
      Person.create! :first_name => 'John', :last_name => 'Doe'
      Person.where(:first_name => 'joHn', :last_name => 'doE').count.should == 1
      Person.where(:first_name => 'John', :last_name => 'Doe').count.should == 0
    end

    it "should correctly replace an existing record when an insensitive-match value is nil" do
      a = Person.create! :first_name => 'John'
      a = Person.create! :first_name => 'John'
      Person.where(:first_name => 'John').count.should == 1
    end

    it "should inherit the id of the existing record" do
      a = Material.create! :name => 'wood'
      b = Material.create! :name => 'wood'
      b.id.should == a.id
    end

    it "should not be a new_record? if it has replaced an existing record" do
      a = Material.create! :name => 'wood'
      b = Material.create! :name => 'wood'
      b.new_record?.should be_false
    end

    it "should be persisted? if it has replaced an existing record" do
      a = Material.create! :name => 'wood'
      b = Material.create! :name => 'wood'
      b.persisted?.should be_true
    end
  end
end