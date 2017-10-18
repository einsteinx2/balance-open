//
//  AccountsListViewController.swift
//  BalanceiOS
//
//  Created by Red Davis on 05/09/2017.
//  Copyright © 2017 Balanced Software, Inc. All rights reserved.
//

import UIKit


internal final class AccountsListViewController: UIViewController
{
    // Fileprivate
    fileprivate let viewModel = AccountsTabViewModel()
    
    // Private
    private let collectionView = StackedCardCollectionView()
    private let titleView = MultilineTitleView()
    
    private let blankStateView = UIView()
    
    // MARK: Initialization
    
    internal required init()
    {
        super.init(nibName: nil, bundle: nil)
        
        self.title = "Accounts"
        self.tabBarItem.image = UIImage(named: "Library")
        
        // Notifications
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(self.syncCompletedNotification(_:)), name: Notifications.SyncCompleted)
    }
    
    internal required init?(coder aDecoder: NSCoder)
    {
        abort()
    }
    
    deinit
    {
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.SyncCompleted)
    }
    
    // MARK: View lifecycle
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        // Collection view
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.backgroundColor = UIColor.black
        self.collectionView.alwaysBounceVertical = true
        self.collectionView.register(reusableCell: InstitutionCollectionViewCell.self)
        self.view.addSubview(self.collectionView)
        
        self.collectionView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        
        // Blank state view
        self.blankStateView.isHidden = true
        self.view.addSubview(self.blankStateView)
        
        self.blankStateView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        
        let noAccountsLabel = UILabel()
        noAccountsLabel.text = "Nothing to see here..."
        noAccountsLabel.textColor = UIColor.white
        noAccountsLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .regular)
        self.blankStateView.addSubview(noAccountsLabel)
        
        noAccountsLabel.snp.makeConstraints { (make) in
            make.bottom.equalTo(self.blankStateView.snp.centerY).offset(-10.0)
            make.centerX.equalToSuperview()
        }
        
        let addAccountButton = UIButton(type: .system)
        addAccountButton.layer.borderColor = UIColor.white.cgColor
        addAccountButton.layer.cornerRadius = 4.0
        addAccountButton.layer.borderWidth = 2.0
        addAccountButton.setTitle("Add an account", for: .normal)
        addAccountButton.setTitleColor(UIColor.white, for: .normal)
        addAccountButton.contentEdgeInsets = UIEdgeInsets(top: 7.0, left: 10.0, bottom: 7.0, right: 10.0)
        addAccountButton.addTarget(self, action: #selector(self.addAccountButtonTapped(_:)), for: .touchUpInside)
        self.blankStateView.addSubview(addAccountButton)
        
        addAccountButton.snp.makeConstraints { (make) in
            make.top.equalTo(self.blankStateView.snp.centerY).offset(10.0)
            make.centerX.equalToSuperview()
        }
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.navigationController?.isNavigationBarHidden = true
        self.reloadData()
    }
    
    // MARK: Data
    
    private func reloadData() {
        self.viewModel.reloadData()
        self.collectionView.reloadData()
        
        self.blankStateView.isHidden = self.viewModel.numberOfSections() > 0
    }
    
    // MARK: Actions
    
    @objc private func addAccountButtonTapped(_ sender: Any) {
        let addAccountViewController = AddAccountViewController()
        let navigationController = UINavigationController(rootViewController: addAccountViewController)
        
        self.present(navigationController, animated: true, completion: nil)
    }
    
    // MARK: Notifications
    
    @objc private func syncCompletedNotification(_ notification: Notification) {
        self.reloadData()
    }
}

// MARK: UICollectionViewDataSource

extension AccountsListViewController: UICollectionViewDataSource
{
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.viewModel.numberOfSections()
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell: InstitutionCollectionViewCell = collectionView.dequeueReusableCell(at: indexPath)
        
        let institution = self.viewModel.institution(forSection: indexPath.row)!
        let viewModel = InstitutionAccountsListViewModel(institution: institution)
        cell.viewModel = viewModel
        
        return cell
    }
}

// MARK: UICollectionViewDelegate

extension AccountsListViewController: UICollectionViewDelegate
{
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        
    }
}
