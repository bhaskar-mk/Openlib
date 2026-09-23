// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import 'dart:convert';

// ====================================================================
// DATA MODELS
// ====================================================================

class BookData {
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String md5;
  final String? publisher;
  final String? info;

  BookData(
      {required this.title,
      this.author,
      this.thumbnail,
      required this.link,
      required this.md5,
      this.publisher,
      this.info});
}

class BookInfoData extends BookData {
  String? mirror;
  final String? description;
  final String? format;

  BookInfoData(
      {required super.title,
      required super.author,
      required super.thumbnail,
      required super.publisher,
      required super.info,
      required super.link,
      required super.md5,
      required this.format,
      required this.mirror,
      required this.description});
}

// ====================================================================
// ANNA'S ARCHIVE SERVICE (ALL FIXES APPLIED)
// ====================================================================

class AnnasArchieve {
  static const String defaultBaseUrl = "https://annas-archive.gd";
  static const String baseUrl = defaultBaseUrl;

  static const List<String> defaultMirrors = [
    "https://annas-archive.gd",
    "https://annas-archive.gl",
    "https://annas-archive.pk",
  ];

  final String currentBaseUrl;
  final Dio dio;

  AnnasArchieve({String? baseUrl})
      : currentBaseUrl = (baseUrl != null && baseUrl.isNotEmpty)
            ? baseUrl
            : defaultBaseUrl,
        dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 10),
            followRedirects: true,
            maxRedirects: 5,
          ),
        );

  Map<String, dynamic> defaultDioHeaders = {
    "user-agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
    "accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "accept-language": "en-US,en;q=0.9",
  };

  String getMd5(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    return pathSegments.isNotEmpty ? pathSegments.last : '';
  }

  String getFormat(String info) {
    final infoLower = info.toLowerCase();
    if (infoLower.contains('pdf')) {
      return 'pdf';
    } else if (infoLower.contains('cbr')) {
      return "cbr";
    } else if (infoLower.contains('cbz')) {
      return "cbz";
    }
    return "epub";
  }

  // Helper function to safely parse potential NaN/Infinity to prevent crash
  // This is a generic safeguard for the third type of error you received.
  dynamic _safeParse(dynamic value) {
    if (value is String) {
      if (value.toLowerCase() == 'nan' || value.toLowerCase() == 'infinity') {
        return null; // Return null or 0 instead of throwing an error
      }
      return value;
    }
    return value;
  }
  
  // --------------------------------------------------------------------
  // _parser FUNCTION (Search Results - Fixed nth-of-type issue)
  // --------------------------------------------------------------------
  List<BookData> _parser(resData, String fileType, {String? activeBaseUrl}) {
    final domain = activeBaseUrl ?? currentBaseUrl;
    var document = parse(resData.toString());

    var bookContainers =
        document.querySelectorAll('div.flex.pt-3.pb-3.border-b');

    List<BookData> bookList = [];

    for (var container in bookContainers) {
      final mainLinkElement =
          container.querySelector('a.line-clamp-\\[3\\].js-vim-focus');
      final thumbnailElement = container.querySelector('a[href^="/md5/"] img');

      if (mainLinkElement == null || mainLinkElement.attributes['href'] == null) {
        continue;
      }

      final String title = mainLinkElement.text.trim();
      final String link = domain + mainLinkElement.attributes['href']!;
      final String md5 = getMd5(mainLinkElement.attributes['href']!);
      final String? thumbnail = thumbnailElement?.attributes['src'];

      // Fix: Use sequential traversal instead of :nth-of-type
      dom.Element? authorLinkElement = mainLinkElement.nextElementSibling;
      dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;
      
      if (authorLinkElement?.attributes['href']?.startsWith('/search?q=') != true) {
          authorLinkElement = null;
      }
      if (publisherLinkElement?.attributes['href']?.startsWith('/search?q=') != true) {
          publisherLinkElement = null;
      }

      final String? authorRaw = authorLinkElement?.text.trim();
      final String? author = (authorRaw != null && authorRaw.contains('icon-'))
          ? authorRaw.split(' ').skip(1).join(' ').trim()
          : authorRaw;
      
      final String? publisher = publisherLinkElement?.text.trim();
      
      final infoElement = container.querySelector('div.text-gray-800');
      // No need for _safeParse here if we only treat info as a string
      final String? info = infoElement?.text.trim(); 
      
      final bool hasMatchingFileType = fileType.isEmpty
          ? (info?.contains(RegExp(r'(PDF|EPUB|CBR|CBZ)', caseSensitive: false)) == true)
          : info?.toLowerCase().contains(fileType.toLowerCase()) == true;

      if (hasMatchingFileType) {
        final BookData book = BookData(
          title: title,
          author: author?.isEmpty == true ? "unknown" : author,
          thumbnail: thumbnail,
          link: link,
          md5: md5,
          publisher: publisher?.isEmpty == true ? "unknown" : publisher,
          info: info,
        );
        bookList.add(book);
      }
    }
    return bookList;
  }
  // --------------------------------------------------------------------

  // --------------------------------------------------------------------
  // _bookInfoParser FUNCTION (Detail Page - Fixed 'unable to get data' error)
  // --------------------------------------------------------------------
  Future<BookInfoData?> _bookInfoParser(resData, url, {String? activeBaseUrl}) async {
    final domain = activeBaseUrl ?? currentBaseUrl;
    var document = parse(resData.toString());
    final main = document.querySelector('div.main-inner'); 
    if (main == null) return null;

    // --- Mirror Link Extraction ---
    String? mirror;
    final slowDownloadLinks = main.querySelectorAll('ul.list-inside a[href*="/slow_download/"]');
    if (slowDownloadLinks.isNotEmpty && slowDownloadLinks.first.attributes['href'] != null) {
        mirror = domain + slowDownloadLinks.first.attributes['href']!;
    }
    // --------------------------------


    // --- Core Info Extraction ---
    
    // Title
    final titleElement = main.querySelector('div.font-semibold.text-2xl'); 
    
    // Author
    final authorLinkElement = main.querySelector('a[href^="/search?q="].text-base');
    
    // Publisher
    dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;
    if (publisherLinkElement?.localName != 'a' || publisherLinkElement?.attributes['href']?.startsWith('/search?q=') != true) {
        publisherLinkElement = null;
    }

    // Thumbnail
    final thumbnailElement = main.querySelector('div[id^="list_cover_"] img');
    
    // Info/Metadata
    final infoElement = main.querySelector('div.text-gray-800');
    
    // Description
    dom.Element? descriptionElement;
    final descriptionLabel = main.querySelector('div.js-md5-top-box-description div.text-xs.text-gray-500.uppercase');
    
    if (descriptionLabel?.text.trim().toLowerCase() == 'description') {
        descriptionElement = descriptionLabel?.nextElementSibling;
    }
    String description = descriptionElement?.text.trim() ?? " ";

    if (titleElement == null) {
      return null;
    }

    final String title = titleElement.text.trim().split('<span')[0].trim(); 
    final String author = authorLinkElement?.text.trim() ?? "unknown";
    final String? thumbnail = thumbnailElement?.attributes['src'];
    
    final String publisher = publisherLinkElement?.text.trim() ?? "unknown";
    // NOTE: If you extract any numeric data from the 'info' string later in your app (e.g., file size or page count)
    // and attempt to convert it to an integer or double, that's where you should use _safeParse.
    final String info = infoElement?.text.trim() ?? ''; 

    return BookInfoData(
      title: title,
      author: author,
      thumbnail: thumbnail,
      publisher: publisher,
      info: info,
      link: url,
      md5: getMd5(url),
      format: getFormat(info),
      mirror: mirror,
      description: description,
    );
  }
  // --------------------------------------------------------------------

  String urlEncoder(
      {required String searchQuery,
      required String content,
      required String sort,
      required String fileType,
      required bool enableFilters,
      String? activeBaseUrl}) {
    final domain = activeBaseUrl ?? currentBaseUrl;
    searchQuery = searchQuery.replaceAll(" ", "+");
    if (!enableFilters) {
      return '$domain/search?q=$searchQuery';
    }
    return '$domain/search?index=&q=$searchQuery&content=$content&ext=$fileType&sort=$sort';
  }

  Future<List<BookData>> searchBooks(
      {required String searchQuery,
      String content = "",
      String sort = "",
      String fileType = "",
      bool enableFilters = true}) async {
    List<String> candidates = [currentBaseUrl];
    for (final m in defaultMirrors) {
      if (!candidates.contains(m)) {
        candidates.add(m);
      }
    }

    dynamic lastError;
    for (int i = 0; i < candidates.length; i++) {
      final currentMirror = candidates[i];
      try {
        final String encodedURL = urlEncoder(
            searchQuery: searchQuery,
            content: content,
            sort: sort,
            fileType: fileType,
            enableFilters: enableFilters,
            activeBaseUrl: currentMirror);

        final response = await dio.get(
          encodedURL,
          options: Options(headers: defaultDioHeaders),
        );
        return _parser(response.data, fileType, activeBaseUrl: currentMirror);
      } on DioException catch (e) {
        lastError = e;
        if (i < candidates.length - 1) {
          continue;
        }
        if (e.type == DioExceptionType.unknown ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          throw "socketException";
        }
        rethrow;
      } catch (e) {
        lastError = e;
        if (i < candidates.length - 1) {
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? "socketException";
  }

  Future<BookInfoData> bookInfo({required String url}) async {
    List<String> urlsToTry = [url];
    try {
      final originalUri = Uri.parse(url);
      for (final mirror in defaultMirrors) {
        final mirrorUri = Uri.parse(mirror);
        if (originalUri.host != mirrorUri.host) {
          final altUri = originalUri.replace(
            scheme: mirrorUri.scheme,
            host: mirrorUri.host,
            port: mirrorUri.hasPort ? mirrorUri.port : null,
          );
          urlsToTry.add(altUri.toString());
        }
      }
    } catch (_) {}

    dynamic lastError;
    for (int i = 0; i < urlsToTry.length; i++) {
      final currentUrl = urlsToTry[i];
      final currentDomain = Uri.tryParse(currentUrl)?.origin;
      try {
        final response = await dio.get(
          currentUrl,
          options: Options(headers: defaultDioHeaders),
        );
        BookInfoData? data = await _bookInfoParser(
          response.data,
          currentUrl,
          activeBaseUrl: currentDomain,
        );
        if (data != null) {
          return data;
        } else {
          throw 'unable to get data';
        }
      } on DioException catch (e) {
        lastError = e;
        if (i < urlsToTry.length - 1) {
          continue;
        }
        if (e.type == DioExceptionType.unknown ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          throw "socketException";
        }
        rethrow;
      } catch (e) {
        lastError = e;
        if (i < urlsToTry.length - 1) {
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? 'unable to get data';
  }
}