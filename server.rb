#!/usr/bin/env ruby 

require "rubygems"
require "bundler"

Bundler.setup(:server)

require 'sinatra'
require 'json'

class Image
	attr_reader :name
	attr_accessor :description,:source

	def initialize name, opts={}
		@name=name
		@description=opts[:description]
		@source=opts[:source]
	end
end

class Device
	attr_reader :id, :info

	attr_accessor :nickname, :provisioned, :image, :last_seen
	attr_accessor :reimage

	alias_method :provisioned?, :provisioned
	alias_method :reimage?, :reimage

	def initialize id, info=nil
		@provisioned=false
		@id=id
		@info=info
		@info||={}
		
		@nickname=@info[:nickname] || @id
	end
end

class ProvisionServer
	attr_reader :images

	def initialize
		@devices = Hash.new
		@images = Hash.new
	end

	def remove_device device_id
		@devices.delete device_id
	end

	def add_device device_id, device_info={}
		response = {}
		device = nil

		if @devices.has_key?(device_id)
			device = @devices[device_id]
			response[:status] = "ok"
		else
			device = Device.new device_id, device_info
			@devices[device_id]=device
			response[:status] = "welcome"
		end

		if device.reimage?
			image = images[device.image]
			response[:image]=image.source
			device.reimage = false
		end

		device.last_seen = Time.now
		response
	end

	def unprovisioned_devices 
		@devices.values.find_all {|device| device.provisioned? == false}.sort{|a,b| a.nickname<=>b.nickname}
	end

	def provisioned_devices
		@devices.values.find_all {|device| device.provisioned?}.sort{|a,b| a.nickname<=>b.nickname}
	end

	def get_device device_id
		@devices[device_id]
	end
end

server = ProvisionServer.new

default_img = Image.new "Default"
default_img.description="Blinky Demo"
default_img.source = <<EOF
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setup(25, GPIO.OUT)

while True:
	GPIO.output(25, GPIO.HIGH)
	time.sleep(1)
	GPIO.output(25, GPIO.LOW)
	time.sleep(1)
EOF

server.images[default_img.name] = default_img

get "/" do
	redirect "devices"
end

### devices

get "/devices" do
	erb :devices, :locals=>{unprovisioned:server.unprovisioned_devices, provisioned:server.provisioned_devices}
end

get "/devices/:id" do
	device=server.get_device params[:id]
	erb :device, :locals=>{device:device, images:server.images}
end


#FIXME: not restful, just lazy
get "/devices/:id/delete" do
	server.remove_device params[:id]
	redirect "/devices"
end

post "/devices/:id" do
	device=server.get_device params[:id]

	device.nickname = params["nickname"]
	device.image = params["image"]
	device.provisioned=true

	device.reimage = true

	redirect "/devices"
end


get "/images" do
	erb :images, :locals=>{images:server.images}
end

get "/images/:id" do
	image = server.images[params[:id]]
	erb :image, :locals=>{image:image}
end

post "/images/:id" do
	image=server.images[params[:id]]

	image.description = params["description"]
	image.source=params["source"]

	redirect "/images"
end




post "/hello" do

	data = JSON.parse(params[:data], symbolize_names:true)
	return {error:"no id given"}.to_json if data[:id] == nil

	response = server.add_device(data[:id], data[:device_info])
	response.to_json
end
