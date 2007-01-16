$(document).ready(function(){

  /* doorblock sorting and pooling */
  var all_blocks = $('#fullpool').html();
  if (all_blocks != '')
  {
    var altered = function(ary) { 
      $.ajax({type: 'POST', url: '/doorway/blocks', data: ary[0].hash});
      $('#fullpool').html(all_blocks).Sortable(doorsort);
      $('#userpool a.del').click(removed);
    }
    var removed = function() {
      $('../../../..', this).remove();
      altered([$.SortSerialize('userpool')]);
    }
    var doorsort = {
      accept: 'blocksort',
      activeclass: 'blockactive',
      hoverclass: 'blockhover',
      helperclass: 'sorthelper',
      opacity: 0.8,
      fx:       200,
      revert: true,
      tolerance: 'intersect',
      onchange: altered
    };
    $('ol.doorblocks').Sortable(doorsort);
    $('#userpool a.del').click(removed);
  }

});
