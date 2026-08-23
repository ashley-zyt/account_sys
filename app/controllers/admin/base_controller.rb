class Admin::BaseController < ApplicationController
	before_action :authenticate_admin!
	layout "admin"
	include OperationLogging
	helper Admin::SelectHelper
end
