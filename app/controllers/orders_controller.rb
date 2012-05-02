# coding: UTF-8

# BillGastro -- The innovative Point Of Sales Software for your Restaurant
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.

class OrdersController < ApplicationController

  def index
    @tables = @current_user.tables
    @categories = @current_vendor.categories.positioned
    @users = User.accessible_by(@current_user).active
    session[:admin_interface] = false
  end

  # happens only in invoice_form if user changes CostCenter or Tax of Order
  def update
    @order = Order.accessible_by(@current_user).find_by_id params[:id]
    if params[:order][:tax_id]
      @order.update_attribute :tax_id, params[:order][:tax_id] 
      @order.items.each { |i| i.update_attribute :tax_id, nil }
      @orders = Order.accessible_by(@current_user).find_all_by_finished(false, :conditions => { :table_id => @order.table_id })
      @cost_centers = CostCenter.accessible_by(@current_user).all
      @taxes = Tax.accessible_by(@current_user).all
      render 'items/update'
    else
      @order.update_attribute(:cost_center_id, params[:order][:cost_center_id]) if params[:order][:cost_center_id]  
      render :nothing => true
    end
  end

  def edit
    @order = Order.accessible_by(@current_user).find_by_id params[:id]
    @table = @order.table
    render 'orders/go_to_order_form'
  end

  def show
    if params[:id] != 'last'
      @order = Order.accessible_by(@current_user).find(params[:id])
    else
      @order = Order.accessible_by(@current_user).find_all_by_finished(true).last
    end
    redirect_to '/' and return if not @order
    @previous_order, @next_order = neighbour_orders(@order)
    respond_to do |wants|
      wants.html
      wants.bill { render :text => generate_escpos_invoice(@order) }
    end
  end

  def by_nr
    @order = Order.find_by_nr params[:nr]
    if @order
      redirect_to order_path(@order)
    else
      redirect_to order_path(Order.last)
    end
  end



  def toggle_admin_interface
    if session[:admin_interface]
      session[:admin_interface] = !session[:admin_interface]
    else
      session[:admin_interface] = true
    end
    @tables = @current_user.tables
  end

  def toggle_tax_colors
    if session[:display_tax_colors]
      session[:display_tax_colors] = !session[:display_tax_colors]
    else
      session[:display_tax_colors] = true
    end
    @orders = Order.accessible_by(@current_user).find_all_by_finished(false, :conditions => { :table_id => Order.find_by_id(params[:id]).table_id })
    @cost_centers = CostCenter.accessible_by(@current_user).all
    @taxes = Tax.accessible_by(@current_user).all
    render 'items/update'
  end

  def print_and_finish
    @order = Order.accessible_by(@current_user).find params[:id]

    is_finished = @order.finished

    if not is_finished
      if @order.nr > @current_vendor.largest_order_number
        @current_vendor.update_attribute :largest_order_number, @order.nr 
      end
      @order.created_at = Time.now
      @order.user = @current_user if mobile?
      @order.finished = true
      @order.printed_from = "#{ request.remote_ip } -> #{ params[:port] }" if params[:port] != '0'
      @order.save
      unlink_orders(@order)
    end

    if params[:port].to_i != 0
      if local_variant?
        # print immediately
        selected_printer = VendorPrinter.find_by_id(params[:port].to_i)
        printer_id = selected_printer.id if selected_printer
        all_printers = initialize_printers
        text = generate_escpos_invoice(@order)
        do_print(all_printers, printer_id, text)
        close_printers(all_printers)
      else
        # print later
        @order.update_attribute :print_pending, true
      end
    end

    @orders = Order.accessible_by(@current_user).find(:all, :conditions => { :table_id => @order.table, :finished => false })
    @order.table.update_attribute :user, nil if @orders.empty?
    @cost_centers = CostCenter.accessible_by(@current_user).find_all_by_active(true)
    @taxes = Tax.accessible_by(@current_user).all

    respond_to do |wants|
      wants.js {
        if is_finished
          # is the case for storno_form
          render :nothing => true
        elsif @orders.empty?
          # is the case for invoice_form
          @tables = @current_user.tables.existing
          render 'go_to_tables'
        else
          # is the case for invoice_form
          render 'go_to_invoice_form'
        end
      }
    end
  end

  def storno
    @order = Order.accessible_by(@current_user).find_by_id params[:id]
  end

  def go_to_order_form # to be called only with /id
    @order = Order.accessible_by(@current_user).find(params[:id])
    @table = @order.table
    @cost_centers = CostCenter.find_all_by_active(true)
    render 'go_to_order_form'
  end

  def receive_order_attributes_ajax
    @cost_centers = CostCenter.accessible_by(@current_user).find_all_by_active true

    if params[:order][:id].empty?
      # The AJAX load on the client side has not succeeded before user submitted the order form.
      # In this case, simply select the first order on the table the user had selected.
      @order = Order.accessible_by(@current_user).find(:all, :conditions => { :finished => false, :table_id => params[:order][:table_id] }).first
    else
      # The AJAX load on the client side has succeeded and we know the order ID.
      @order = Order.accessible_by(@current_user).find_by_id params[:order][:id]
    end

    if @order
      # Todo set user of order
      @order.update_attributes params[:order]
      params[:items].to_a.each do |item_params|
        item_id = item_params[1][:id]
        if item_id
          item = Item.find_by_id(item_id)
          if item_params[1][:x]
            item.update_attribute :hidden, true
          else
            item_params[1].delete(:id)
            Item.find_by_id(item_id).update_attributes(item_params[1])
          end
        else
          @order.items << Item.new(item_params[1])
        end
      end
    else # create it
      @order = Order.new params[:order]
      @order.nr = get_next_unique_and_reused_order_number
      @order.cost_center = @current_vendor.cost_centers.first
      @order.user = @current_user
      @order.vendor = @current_vendor
      @order.company = @current_company
      params[:items].to_a.each do |item_params|
        @order.items << Item.new(item_params[1])
      end
    end

    @order.sum = @order.calculate_sum
    @order.table.update_attribute :user, @order.user
    @order.save
    @order.reload
    @order.items.where( :user_id => nil, :preparation_user_id => nil, :delivery_user_id => nil ).each do |i|
      i.update_attributes :user_id => @current_user.id, :vendor_id => @current_vendor.id, :company_id => @current_company.id, :preparation_user_id => i.article.category.preparation_user_id, :delivery_user_id => @current_user.id
    end
    @order.set_priorities

    if @order.nr > @current_vendor.largest_order_number
      @current_vendor.update_attribute :largest_order_number, @order.nr 
    end

    if @order.items.existing.size.zero?
      @current_vendor.unused_order_numbers << @order.nr
      @current_vendor.save
      @order.delete
      @order.table.user = nil
      @order.table.save
      @tables = @current_user.tables.existing
      render 'go_to_tables' and return
    end

    group_identical_items @order

    @order.reload

    if local_variant?
      # print coupons for kitchen, bar, etc.
      printers = initialize_printers
      printers.each do |id, params|
        normal   = generate_escpos_items @order, id, 0
        takeaway = generate_escpos_items @order, id, 1
        do_print printers, id, normal
        do_print printers, id, takeaway
      end
      close_printers printers
    end

    @taxes = Tax.accessible_by(@current_user).all
    @tables = @current_user.tables.existing

    case params[:state][:action]
      when 'save_and_go_to_tables'
        render 'go_to_tables'
      when 'save_and_go_to_invoice'
        @orders = Order.accessible_by(@current_user).find(:all, :conditions => { :table_id => @order.table.id, :finished => false })
        session[:display_tax_colors] = @current_vendor.country == 'de' or @current_vendor.country == 'cc'
        render 'go_to_invoice_form'
      when 'clear_order_and_go_back'
        @order.table.update_attribute :user_id, nil
        @tables = @current_user.tables.existing
        @order.destroy
        render 'go_to_tables'
      when 'move_order_to_table'
        move_order_to_table @order, params[:target_table]
        @tables = @current_user.tables.existing
        render 'go_to_tables'
    end
  end

  def last_invoices
    @unsettled_orders = Order.accessible_by(@current_user).find(:all, :conditions => { :settlement_id => nil, :finished => true, :user_id => @current_user.id })
    if @current_user.role.permissions.include? 'finish_all_settlements'
      @users = @current_vendor.users
    elsif @current_user.role.permissions.include? 'finish_own_settlement'
      @users = [@current_user]
    else
      @users = []
    end
  end

  private

    def unlink_orders(order)
      parent_order = order.order
      order.items.each { |i| i.update_attribute :item_id, nil }
      order.update_attribute :order_id, nil
      order.reload # unlink also in memory
      if parent_order
        parent_order.items.each { |i| i.update_attribute :item_id, nil }
        parent_order.update_attribute :order_id, nil
      end
    end

    def move_order_to_table(order, target_table_id)
      unlink_orders(order)
      this_table = order.table
      target_order = Order.find(:all, :conditions => { :table_id => target_table_id, :finished => false }).first

      if target_order
        order.items.each { |i| i.update_attribute :order, target_order }
        order.reload # unlink items also in memory
        order.destroy
        target_order.sum = target_order.calculate_sum
        target_order.save
        group_identical_items(target_order)
      else
        order.update_attribute :table_id, target_table_id
      end

      # update table users and colors
      unfinished_orders_on_this_table = Order.find(:all, :conditions => { :table_id => this_table.id, :finished => false })
      this_table.update_attribute :user, nil if unfinished_orders_on_this_table.empty?

      Table.accessible_by(@current_user).find_by_id(target_table_id).update_attribute :user, order.user
    end

    def group_identical_items(o)
      items = o.items
      n = items.size - 1
      0.upto(n-1) do |i|
        (i+1).upto(n) do |j|
          Item.transaction do
            if (items[i].article_id  == items[j].article_id and
                items[i].quantity_id == items[j].quantity_id and
                items[i].options     == items[j].options and
                items[i].usage       == items[j].usage and
                items[i].price       == items[j].price and
                items[i].comment     == items[j].comment and
                not items[i].destroyed?
               )
              items[i].count += items[j].count
              items[i].printed_count += items[j].printed_count
              result = items[i].save
              raise "Couldn't save item during grouping. Oops!" if not result
              items[j].destroy
            end
          end
        end
      end
      o.reload
    end

    def neighbour_orders(order)
      orders = Order.accessible_by(@current_user).find_all_by_finished(true)
      idx = orders.index(order)
      previous_order = orders[idx-1] if idx
      previous_order = order if previous_order.nil?
      next_order = orders[idx+1] if idx
      next_order = order if next_order.nil?
      return previous_order, next_order
    end

    def reduce_stocks(order)
      order.items.each do |item|
        item.article.ingredients.each do |ingredient|
          ingredient.stock.balance -= item.count * ingredient.amount
          ingredient.stock.save
        end
      end
    end

end
