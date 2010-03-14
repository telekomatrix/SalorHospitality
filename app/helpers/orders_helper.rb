module OrdersHelper

  def generate_js_variables(categories)

    articleslist =
    "var articleslist = new Array();" +
    categories.collect{ |cat|
      "\narticleslist[#{ cat.id }] = \"" +
      cat.articles_in_menucard.collect{ |art|
        action = art.quantities.empty? ? "add_new_item_a(#{ art.id });" : "display_quantities(#{ art.id });"
        "<tr><td class='article' onclick='#{ action }' onmousedown='highlight_button(this)' onmouseup='restore_button(this)'>#{ art.name }</td></tr>"
      }.to_s + '";'
    }.to_s

    quantitylist =
    "\n\nvar quantitylist = new Array();" +
    categories.collect{ |cat|
      cat.articles_in_menucard.collect{ |art|
        next if art.quantities.empty?
        "\nquantitylist[#{ art.id }] = \"" +
        art.quantities.collect{ |qu|
          "<tr><td class='quantity' onclick='add_new_item_q(#{ qu.id })' onmousedown='highlight_button(this)' onmouseup='restore_button(this)'>#{ qu.name }</td></tr>"
        }.to_s + '";'
      }.to_s
    }.to_s

    itemdetails_q =
    "\n\nvar itemdetails_q = new Array();" +
    categories.collect{ |cat|
      cat.articles_in_menucard.collect{ |art|
        art.quantities.collect{ |qu|
          "\nitemdetails_q[#{ qu.id }] = new Array( '#{ qu.article.id }', '#{ qu.article.name }', '#{ qu.name }', '#{ qu.price }', '#{ qu.article.description }', '#{ compose_item_label(qu) }');"
        }.to_s
      }.to_s
    }.to_s
    

    itemdetails_a =
    "\n\nvar itemdetails_a = new Array();" +
    categories.collect{ |cat|
      cat.articles_in_menucard.collect{ |art|
        "\nitemdetails_a[#{ art.id }] = new Array( '#{ art.id }', '#{ art.name }', '#{ art.name }', '#{ art.price }', '#{ art.description }', '#{ compose_item_label(art) }');"
      }.to_s
    }.to_s


    @designator = 'DESIGNATOR'
    @sort = 'SORT'
    @articleid = 'ARTICLEID'
    @quantityid = 'QUANTITYID'
    @price = 'PRICE'
    @label = 'LABEL'
    @count = 1

    new_item_html = render 'items/item', :locals => { :sort => @sort, :articleid => @articleid, :quantityid => @quantityid, :label => @label, :designator => @designator, :count => @count, :price => @price }
    new_item_html_var = "\n\nvar new_item_html = \"#{ escape_javascript new_item_html }\""

    return articleslist + quantitylist + itemdetails_a + itemdetails_q + new_item_html_var
  end



  def generate_js_functions

    flash_button = 'function highlight_button(element) {
                      restorecolor = element.style.backgroundColor;
                      element.style.backgroundColor = "#777777";
                   }
                   function restore_button(element) {
                      element.style.backgroundColor = restorecolor;
                   }'
                   

    display_articles   = "function display_articles(cat_id) { $('articlestable').innerHTML = articleslist[cat_id]; $('quantitiestable').innerHTML = '&nbsp;'; }\n"

    display_quantities = "function display_quantities(art_id) { $('quantitiestable').innerHTML = quantitylist[art_id]; }\n"

    add_new_item_q = "function add_new_item_q(qu_id) {
                      var timestamp = new Date().getTime();
                      var sort = timestamp.toString().substr(-9,9);
                      var desig = 'new_' + sort;
                      new_item_html_modified = new_item_html.replace(/DESIGNATOR/g, desig);
                      new_item_html_modified = new_item_html_modified.replace(/SORT/g, sort );
                      new_item_html_modified = new_item_html_modified.replace(/LABEL/g,  itemdetails_q[qu_id][5] );
                      new_item_html_modified = new_item_html_modified.replace(/PRICE/g,  itemdetails_q[qu_id][3] );
                      new_item_html_modified = new_item_html_modified.replace(/ARTICLEID/g, itemdetails_q[qu_id][0] );
                      new_item_html_modified = new_item_html_modified.replace(/QUANTITYID/g, qu_id );
                      $('itemstable').insert({ top: new_item_html_modified });
                      $('order_sum').value = parseFloat($('order_sum').value) + parseFloat(itemdetails_q[qu_id][3]);
                    }"
    add_new_item_a = "function add_new_item_a(art_id) {
                      var timestamp = new Date().getTime();
                      var sort = timestamp.toString().substr(-9,9);
                      var desig = 'new_' + sort;
                      new_item_html_modified = new_item_html.replace(/DESIGNATOR/g, desig);
                      new_item_html_modified = new_item_html_modified.replace(/SORT/g, sort);
                      new_item_html_modified = new_item_html_modified.replace(/LABEL/g,  itemdetails_a[art_id][5] );
                      new_item_html_modified = new_item_html_modified.replace(/PRICE/g,  itemdetails_a[art_id][3] );
                      new_item_html_modified = new_item_html_modified.replace(/ARTICLEID/g, itemdetails_a[art_id][0] );
                      new_item_html_modified = new_item_html_modified.replace(/QUANTITYID/g, '' );
                      document.getElementById('quantitiestable').innerHTML = '&nbsp;';
                      $('itemstable').insert({ top: new_item_html_modified });
                      $('order_sum').value = parseFloat($('order_sum').value) + parseFloat(itemdetails_a[art_id][3]);
                    }"
                    
    increment_item_func = "function increment_item(desig) {
                             $('count_' + desig).innerHTML = $('order_items_attributes_' + desig + '_count').value++ + 1;
                             $('order_sum').value = parseFloat($('order_sum').value) + parseFloat($(desig + '_price').value);
                           }"
                           
    decrement_item_func = "function decrement_item(desig) {
                             var i;
                             i = parseInt($('order_items_attributes_' + desig + '_count').value);
                             if (i < 2) { Effect.DropOut('item_' + desig); };
                             $('count_' + desig).innerHTML = $('order_items_attributes_' + desig + '_count').value-- - 1;
                             $('order_sum').value = parseFloat($('order_sum').value) - parseFloat($(desig + '_price').value);
                           }"
    remove_item_func = "function remove_item(desig) {
                             Effect.DropOut('item_' + desig );
                             $('order_items_attributes_' + desig + '__delete').value = 1;
                             $('order_sum').value = parseFloat($('order_sum').value) - ( parseFloat($('order_items_attributes_' + desig + '_count').value) * parseFloat($(desig + '_price').value));

                        }"
    
    return display_articles + display_quantities + add_new_item_q + add_new_item_a + increment_item_func + decrement_item_func + flash_button + remove_item_func
  end

  def compose_item_label(input)
    if input.class == Quantity
      label = "#{ input.article.name }<br><small>#{ input.price } EUR, #{ input.name }</small>"
      #label += '<small>, ' + input.article.description if !input.article.description.empty?
    else
      label = "#{ input.name }<br><small>#{ input.price } EUR</small>"
    end
    return label
  end



end
