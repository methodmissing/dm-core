require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

describe DataMapper::Callsite do
  
  before(:all) do
    class ::Product
      include DataMapper::Resource

      property :id,          Serial
      property :type,        Class
      property :name,        String
      property :category_id, Integer
      property :active,      Boolean
      
    end
    
    class ::Configuration
      include DataMapper::Resource
      
      property :element, String
      property :value, String
      
    end   
    @query = DataMapper::Query.new( DataMapper::Repository.new(:default), Product, :fields => [:id] ) 
  end
  
   describe "in general" do

     before(:all) do
       @callsite = DataMapper::Callsite.new( Product, :default, 1234 )
     end

     it 'should not track any links when initialized' do
       @callsite.links?().should eql( false )
     end

     it 'should be able to yield initial fields for the callsite' do
       @callsite.fields.should == Extlib::SimpleSet.new( [:type, :id] )
     end

     it 'should have a hash representation' do
       @callsite.to_hash.should == { :fields => [:type, :id] }
     end
     
     it 'should be able to optimize a given query instance' do
       @callsite.optimize( @query ).fields.size.should == 2
     end
  
     it 'should have a query representation' do
       @callsite.to_query.fields.map{|f| f.name.to_s }.sort.should == %w(id type)
     end
  
     describe "for a model with an identity field" do

       it 'should be able to infer it\'s identity field' do
         @callsite.identity_field.should == :id
       end

       describe "inheritable" do

         it 'should identify itself as inheritable' do
           @callsite.inheritable?().should eql( true )
         end    

         it 'should be able to infer it\'s inheritance field' do
           @callsite.inheritance_field.should == :type
         end

       end

     end  
  
     describe "for a model without an identity field" do

       before(:all) do
         @callsite = DataMapper::Callsite.new( Configuration, :default, 1234 )
       end

       it 'should be able to infer it\'s identity field' do
         @callsite.identity_field.should == nil
       end

       describe "not inhertiable" do

         it 'should not identify itself as inheritable' do
           @callsite.inheritable?().should eql( false )
         end    

       end

     end
       
   end 
    
end  