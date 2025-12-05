"""
Pagination utilities for database queries.
"""
from math import ceil
from django.core.paginator import Paginator, EmptyPage, PageNotAnInteger


def paginate_queryset(queryset, page_number, per_page=20):
    """
    Paginate a queryset or list.
    
    Args:
        queryset: Django queryset or list to paginate
        page_number: Current page number (1-indexed)
        per_page: Number of items per page
        
    Returns:
        dict: {
            'items': list of items for current page,
            'page_number': current page number,
            'total_pages': total number of pages,
            'total_items': total number of items,
            'has_previous': bool,
            'has_next': bool,
            'previous_page': int or None,
            'next_page': int or None,
        }
    """
    paginator = Paginator(queryset, per_page)
    
    try:
        page = paginator.page(page_number)
    except PageNotAnInteger:
        page = paginator.page(1)
        page_number = 1
    except EmptyPage:
        page = paginator.page(paginator.num_pages)
        page_number = paginator.num_pages
    
    return {
        'items': list(page.object_list),
        'page_number': page_number,
        'total_pages': paginator.num_pages,
        'total_items': paginator.count,
        'has_previous': page.has_previous(),
        'has_next': page.has_next(),
        'previous_page': page.previous_page_number() if page.has_previous() else None,
        'next_page': page.next_page_number() if page.has_next() else None,
        'per_page': per_page,
    }


def paginate_sql_results(cursor_results, page_number, per_page=20):
    """
    Paginate results from a raw SQL query.
    
    Args:
        cursor_results: List of tuples from cursor.fetchall()
        page_number: Current page number (1-indexed)
        per_page: Number of items per page
        
    Returns:
        dict: Same structure as paginate_queryset
    """
    total_items = len(cursor_results)
    total_pages = ceil(total_items / per_page) if total_items > 0 else 1
    
    # Validate page number
    if page_number < 1:
        page_number = 1
    elif page_number > total_pages:
        page_number = total_pages
    
    # Calculate slice indices
    start_index = (page_number - 1) * per_page
    end_index = start_index + per_page
    
    # Get items for current page
    items = cursor_results[start_index:end_index]
    
    return {
        'items': items,
        'page_number': page_number,
        'total_pages': total_pages,
        'total_items': total_items,
        'has_previous': page_number > 1,
        'has_next': page_number < total_pages,
        'previous_page': page_number - 1 if page_number > 1 else None,
        'next_page': page_number + 1 if page_number < total_pages else None,
        'per_page': per_page,
    }

