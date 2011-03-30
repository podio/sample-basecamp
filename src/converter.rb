require 'podio'
require 'basecamp'
require 'yaml'

#Initialize API Interfaces
#FIXME: Reenable SSL verify in net_http.rb

API_CONFIG = YAML::load(File.open('api_config.yml')) #Podio API config
api_config = API_CONFIG

Basecamp.establish_connection!(api_config['basecamp_url'], api_config['basecamp_username'], api_config['basecamp_password'], true)
@basecamp = Basecamp.new

Podio.configure do |config|
  config.api_key = api_config['api_key']
  config.api_secret = api_config['api_secret']
  config.debug = true
end
Podio.client = Podio::Client.new
Podio.client.get_access_token(api_config['login'], api_config['password'])

def choose_podio_org
	puts 'This script will create one space/project.
Choose the Organization for these spaces now'
	Podio::Organization.find_all.each do |org|
	  puts "\t#{org['org_id']}: #{org['name']}"
	end
	puts "Org id: "
	org_id = gets.chomp
end

def date_converter(date, s)
	if s == true
		date.to_s[5..-1].gsub!(/ /, '-')+ " 00:00:00"
	else
		date = date.to_s[0..-5]	
	end
	p date
	date	
end

def import_milestones(project)
	@basecamp.milestones(project.id).inject({}) {|hash, m|
		items = Podio::Item.find_all_by_external_id(@apps['Milestones']['app_id'], m['id'])
		if items.count <= 0 #Check doesn't exist
			res = Podio::Item.create(@apps['Milestones']['app_id'], {:external_id=>m['id'].to_s, 'fields'=>[
				{:external_id=>'title', 'values'=>[{'value'=>m['title']}]},
				{:external_id=>'whens-it-due', 'values'=>[{'start'=>date_converter(m['created-on'], false)}]}
				#{'end'=>date_converter(m['deadline'], true)}
				
				]})
			p res
			hash[m['id']] = {:item=>m, :podio_id=>res['item_id']}
		else
			hash[m['id']] = {:item=>m, :podio_id=>items.all[0]['item_id']}
		end
		hash
	}
end

def import_messages(project, milestones)
	Basecamp::Message.archive(project_id=project.id).each do |m|
		m = Basecamp::Message.find(m.id)
		
		if m.milestone_id != 0 #FIXME: Refactor to block, or something
			val = [{:value=>milestones[m.milestone_id][:podio_id]}]
		else
			val = []
		end
		
		if Podio::Item.find_all_by_external_id(@apps['Messages']['app_id'], m.id).count <= 0 #Check doesn't exist
			Podio::Item.create(@apps['Messages']['app_id'], {:external_id=>m.id.to_s, 'fields'=>[
				{:external_id=>'title', 'values'=>[{:value=>m.title}]},
				{:external_id=>'body', 'values'=>[{:value=>m.body}]},
				{:external_id=>'originally-posted', 'values'=>[:start=>date_converter(m.posted_on, false)]},
				{:external_id=>'categories', 'values'=>[{:value=>Basecamp::Category.find(m.category_id).name}]},
				{:external_id=>'milestone', 'values'=>val}
			]})
		end
	end
end

def cache_project_users(project)
	@basecamp.people(project.company.id, project.id).inject({}) {|users, user|
			users[user['id']] = user
			users
	}
end

org_id = 8138
space_id = 24884
spaces = Podio::Space.find_all_for_org(org_id).inject({}) {|obj, x|
	obj[x['name']]=x
	obj
}

Basecamp::Project.find(:all).each {|project|
	# users = cache_project_users(project)
	if !spaces.has_key?(project.name)
		puts project.name+' not in Podio yet'
		spaces[project.name]= Podio::Space.create(
			{'org_id'=>org_id, 'name'=>project.name,
			 'post_on_new_app' => false, 'post_on_new_member' => false }
		)
	else
		puts "Already in Podio"
		space = spaces[project.name]
	end
	apps = Podio::Application.find_all_for_space(space['space_id'].to_i)
	@apps = apps.inject({}) {|hash,app|
		if app['status'] == 'active'
			hash[app['config']['name']] = app
		end
		hash
	}
	
	milestones = import_milestones(project)
	import_messages(project, milestones)
}