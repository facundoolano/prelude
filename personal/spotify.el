;;; helm-spotify.el --- Control Spotify with Helm.
;; Copyright 2013 Kris Jenkins
;;
;; Author: Kris Jenkins <krisajenkins@gmail.com>
;; Maintainer: Kris Jenkins <krisajenkins@gmail.com>
;; Keywords: helm spotify
;; URL: https://github.com/krisajenkins/helm-spotify
;; Created: 14th October 2013
;; Version: 0.1.1
;; Package-Requires: ((helm "0.0.0") (multi "2.0.0"))

;;; Commentary:
;;
;; A search & play interface for Spotify.
;;
;; Currently supports OSX, Linux & Windows.
;;
;; (Want support for another platform? There's a guide in the github README.)

;;; Code:

;;; API Reference: https://developer.spotify.com/technologies/web-api/
(require 'url)
(require 'json)
(require 'helm)
(require 'multi)

(defun alist-get (symbols alist)
  "Look up the value for the chain of SYMBOLS in ALIST."
  (if symbols
      (alist-get (cdr symbols)
		 (assoc (car symbols) alist))
    (cdr alist)))

(defmulti spotify-play-href (href)
  "Get the Spotify app to play the object with the given HREF."
  system-type)

(defmulti-method spotify-play-href 'darwin
  (href)
  (shell-command (format "osascript -e 'tell application %S to play track %S'"
			 "Spotify"
			 href)))

(defmulti-method spotify-play-href 'gnu/linux
  (href)
  (shell-command "dbus-send  --print-reply --session --type=method_call --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Pause")
  (shell-command (format "dbus-send --session --type=method_call --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.OpenUri \"string:%s\""
			 href)))

(defmulti-method spotify-play-href 'windows-nt
  (href)
  (shell-command (format "explorer %S" href)))

(defmulti-method-fallback spotify-play-href
  (href)
  (message "Sorry, helm-spotify does not support playing tracks on %S." system-type))

(defun spotify-play-track (track)
  "Get the Spotify app to play the TRACK."
  (spotify-play-href (alist-get '(uri) track)))

(defun spotify-get-track (album-href)
  (let ((response (with-current-buffer
                   (url-retrieve-synchronously album-href)
                   (goto-char url-http-end-of-headers)
                   (json-read))))
    (aref (alist-get '(tracks items) response) 0)))

(defun spotify-play-album (track)
  "Get the Spotify app to play the album for this TRACK."
  (let ((first-track (spotify-get-track (alist-get '(album href) track))))
    (spotify-play-href (alist-get '(uri) first-track))))


(defun spotify-search (search-term type)
  "Search spotify for SEARCH-TERM, returning the results as a Lisp structure."
  (let ((a-url (format "https://api.spotify.com/v1/search?q=%s&type=%s" search-term type)))
    (with-current-buffer
	(url-retrieve-synchronously a-url)
      (goto-char url-http-end-of-headers)
      (json-read))))

(defun spotify-format-track (track)
  "Given a TRACK, return a a formatted string suitable for display."
  (let ((track-name   (alist-get '(name) track))
	(track-length (/ (alist-get '(duration_ms) track) 1000))
	(album-name   (alist-get '(album name) track))
	(artist-names (mapcar (lambda (artist)
				(alist-get '(name) artist))
			      (alist-get '(artists) track))))
    (format "%s (%dm%0.2ds)\n%s - %s"
	    track-name
	    (/ track-length 60) (mod track-length 60)
	    (mapconcat 'identity artist-names "/")
	    album-name)))

(defun spotify-search-track-formatted (search-term)
  (mapcar (lambda (track))
      (cons (spotify-format-track track) track)
    (alist-get '(tracks items) (spotify-search search-term "track"))))

(defun spotify-search-album-formatted (search-term)
  (elt
    (alist-get '(albums items) (spotify-search search-term "album")) 0))


(defun helm-spotify-search ()
  (spotify-search-formatted helm-pattern))

(defun helm-spotify-actions-for-track (actions track)
  "Return a list of helm ACTIONS available for this TRACK."
  `((,(format "Play Track - %s" (alist-get '(name) track))       . spotify-play-track)
    (,(format "Play Album - %s" (alist-get '(album name) track)) . spotify-play-album)
    ("Show Track Metadata" . pp)))

;;;###autoload
(defvar helm-source-spotify-track-search
  '((name . "Spotify")
    (volatile)
    (delayed)
    (multiline)
    (requires-pattern . 2)
    (candidates-process . helm-spotify-search)
    (action-transformer . helm-spotify-actions-for-track)))

;;;###autoload
(defun helm-spotify ()
  "Bring up a Spotify search interface in helm."
  (interactive)
  (helm :sources '(helm-source-spotify-track-search))
  :buffer "*helm-spotify*")

(provide 'helm-spotify)
;;; helm-spotify.el ends here

(defun spotify-search-and-play-track (search-term)
  (interactive "sSong name: ")
  (spotify-play-track (car (spotify-search-track-formatted search-term))))

(defun spotify-search-and-play-album (search-term)
  (interactive "sSong name: ")
  (spotify-play-track (spotify-search-album-formatted search-term)))
