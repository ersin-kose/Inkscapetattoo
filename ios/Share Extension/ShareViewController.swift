//
//  ShareViewController.swift
//  Share Extension
//
//  Based on receive_sharing_intent example
//
import receive_sharing_intent

class ShareViewController: RSIShareViewController {

    // Return false if you don't want to redirect to host app automatically.
    // Default is true
    override func shouldAutoRedirect() -> Bool {
        return true
    }

    // Optional: change label of Post button
    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "Send"
    }
}
